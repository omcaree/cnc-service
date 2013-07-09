// Assembly code for BeagleBone Black PRU to do basic CNC Stepper Motor control
// 	Written by Owen McAree (owen@aero-box.co.uk)
//
// Pinouts are:
//		X direction	-	P9_31	(PRU_R30_0)
//		X step 		-	P9_29	(PRU_R30_1)
//		Y direction	-	P9_30	(PRU_R30_2)
//		Y step 		-	P9_28	(PRU_R30_3)
//		Z direction	-	P9_27	(PRU_R30_5)
//		Z step 		-	P9_25	(PRU_R30_7)
//	Code starts by initialising 10 integers in the shared memory space
//	These correspond to:
//		0	- Status
//					Gets set to 1 when PRU is waiting for new command
//					No other memory should be changed until the status equals 1
//					This must be set to 0 to set the PRU running
//		1-3 - Current X, Y, Z position
//					All positions are in steps, that is stepper motor increments
//					All position values are unsigned, so the default 'origin' is
//					0x7FFFFFFF.
//					This can be set (when status==1), to change the origin position
//		4-6 - Target X, Y, Z position
//					The target for the next movement (set status to 0 to start moving)
//		7-9 - X, Y, Z PWM (half) period
//					These control the speed of each axis by setting the delay between
//					motor steps. Note that these values are HALF the time period, so
//					a value of 1000 would result in 2000 cycles between pulses.
//					1 cycle ~ 180ns		(TODO: Determine this accurately)
//
//	Executing this code depends largely on how you choose to call it (I am using 
//	my own node.js module, node-pru), but in pseudo-code it goes like this
//
//		Init PRU
//		Set up interrupt handler (see below)
//		Execute PRU code
//		Catch interrupt
//			Update target positions
//			Update target speeds (PWM periods)
//			Set status to 0
//			Clear interrupt
//		(PRU executes)
//		Poll current position periodically (if desired, to update a display for example)
//		Catch next interrupt (ad infinitum...)
//		Terminate PRU

.origin 0
.entrypoint START
#include "prucode.hp"

// Set up some useful constants
#define MIDPOINT 		0x7FFFFFFF		// Default midpoint of each axis (in steps)
#define DEFAULT_PERIOD	0xFFFF			// Default (half) PWM time period

START:
// Preamble to set up OCP and shared RAM
	LBCO	r0, CONST_PRUCFG, 4, 4		// Enable OCP master port
	CLR 	r0, r0, 4					// Clear SYSCFG[STANDBY_INIT] to enable OCP master port
	SBCO	r0, CONST_PRUCFG, 4, 4
	MOV		r0, 0x00000120				// Configure the programmable pointer register for PRU0 by setting c28_pointer[15:0]
	MOV		r1, CTPPR_0					// field to 0x0120.  This will make C28 point to 0x00012000 (PRU shared RAM).
	ST32	r0, r1
	
// Set up the default values in memory
// Shared memory map registers
//	Int 0		- Status
//	Ints 1-3 	- Current X, Y, Z step
//	Ints 4-6 	- Commaned X, Y, Z step
//	Ints 7-9 	- Commanded X, Y, Z half period ('speed')
//	Ints 10+	- Occasionally used for debugging
SETUP:
	MOV		r0, MIDPOINT						// Centre point
	MOV		r1, DEFAULT_PERIOD					// Default time period
	MOV		r2, 0								// No status
	
	SBCO	r3, CONST_PRUSHAREDRAM, 0, 4		// Clear status register
	SBCO	r0, CONST_PRUSHAREDRAM, 4, 4		// Set X to zero
	SBCO	r0, CONST_PRUSHAREDRAM, 8, 4		// Set Y to zero
	SBCO	r0, CONST_PRUSHAREDRAM, 12, 4		// Set Z to zero
	SBCO	r0, CONST_PRUSHAREDRAM, 16, 4		// Set X Target to zero
	SBCO	r0, CONST_PRUSHAREDRAM, 20, 4		// Set Y Target to zero
	SBCO	r0, CONST_PRUSHAREDRAM, 24, 4		// Set Z Target to zero
	SBCO	r1, CONST_PRUSHAREDRAM, 28, 4		// Set X Period to default
	SBCO	r1, CONST_PRUSHAREDRAM, 32, 4		// Set Y Period to detault
	SBCO	r1, CONST_PRUSHAREDRAM, 36, 4		// Set Z Period to detault

// Start the useful things here
// Label is used later to keep program going indefinately (without resetting the memory)
RUN:
	// Pull all the step pins low before doing anything
	CLR		r30.t1
	CLR		r30.t3
	CLR		r30.t7
	
	// Interrupt the calling code and wait for memory to be updated
	MOV		r31.b0, PRU0_ARM_INTERRUPT+16		// Fire interrupt to inform calling code we're ready to go
	MOV		r11, 1								// Set status bit high
	SBCO	r11, CONST_PRUSHAREDRAM, 0, 4
WAIT1:											// Loop until status bit set low
	LBCO	r11, CONST_PRUSHAREDRAM, 0, 4		// TODO: Replace this with interrupt from host
	QBEQ	WAIT1, r11, 1

	// Once data is up to date (targets and speeds set), read it all in
	LBCO	r0, CONST_PRUSHAREDRAM, 4, 36		// Read in data from ram

// Calculate the number of steps required in each axis, and set the direction pin
// Calculate X displacement (and direction)
	QBGT	X_POSITIVE, r0, r3					// Check if target or current value is bigger (to determine direction)
	QBLE	X_NEGATIVE, r0, r3
X_POSITIVE:
	CLR		r30.t0
	SUB		r0, r3, r0
	JMP		X_CALC_DONE
X_NEGATIVE:
	SET		r30.t0
	SUB		r0, r0, r3
X_CALC_DONE:

// Calculate Y displacement (and direction)
	QBGT	Y_POSITIVE, r1, r4
	QBLE	Y_NEGATIVE, r1, r4
Y_POSITIVE:
	CLR		r30.t2
	SUB		r1, r4, r1
	JMP		Y_CALC_DONE
Y_NEGATIVE:
	SET		r30.t2
	SUB		r1, r1, r4
Y_CALC_DONE:

// Calculate Z displacement (and direction)
	QBGT	Z_POSITIVE, r2, r5
	QBLE	Z_NEGATIVE, r2, r5
Z_POSITIVE:
	CLR		r30.t5
	SUB		r2, r5, r2
	JMP		Z_CALC_DONE
Z_NEGATIVE:
	SET		r30.t5
	SUB		r2, r2, r5
Z_CALC_DONE:
	
// Loop over all directions
LOOP1:
//Update X
	SUB		r6, r6, 1						// Calculate X hold time remaining
	QBNE	SKIP_X, r6, 0					// If we're still holding, don't touch the output
	QBEQ	SKIP_X, r0, 0					// If we've reached the target position, don't touch the output
	LBCO	r6, CONST_PRUSHAREDRAM, 28, 4	// If we're updaing the output, reload the hold time for the next cycle
	XOR		r30, r30, 1<<1					// Toggle the step pin
	QBBC	SKIP_X, r30.t1					// If step pin is low, don't increment step counters
	SUB		r0,	r0, 1						// Decrement steps remaining
	LBCO	r10, CONST_PRUSHAREDRAM, 4, 4	// Update current step position in shared memory
	QBBC	UPDATE_X_ADD, r30.t0
	QBBS	UPDATE_X_SUB, r30.t0
UPDATE_X_ADD:
	ADD		r10, r10, 1
	SBCO	r10, CONST_PRUSHAREDRAM, 4, 4
	JMP		SKIP_X
UPDATE_X_SUB:
	SUB		r10, r10, 1
	SBCO	r10, CONST_PRUSHAREDRAM, 4, 4
SKIP_X:

//Update Y
	SUB		r7, r7, 1						// Calculate Y hold time remaining
	QBNE	SKIP_Y, r7, 0					// If we're still holding, don't touch the output
	QBEQ	SKIP_Y, r1, 0					// If we've reached the target position, don't touch the output
	LBCO	r7, CONST_PRUSHAREDRAM, 32, 4	// If we're updaing the output, reload the hold time for the next cycle
	XOR		r30, r30, 1<<3					// Toggle the step pin
	QBBC	SKIP_Y, r30.t3					// If step pin is low, don't increment step counters
	SUB		r1,	r1, 1						// Decrement steps remaining
	LBCO	r10, CONST_PRUSHAREDRAM, 8, 4	// Update current step position in shared memory
	QBBC	UPDATE_Y_ADD, r30.t2
	QBBS	UPDATE_Y_SUB, r30.t2
UPDATE_Y_ADD:
	ADD		r10, r10, 1
	SBCO	r10, CONST_PRUSHAREDRAM, 8, 4
	JMP		SKIP_Y
UPDATE_Y_SUB:
	SUB		r10, r10, 1
	SBCO	r10, CONST_PRUSHAREDRAM, 8, 4
SKIP_Y:

//Update Z
	SUB		r8, r8, 1						// Calculate Z hold time remaining
	QBNE	SKIP_Z, r8, 0					// If we're still holding, don't touch the output
	QBEQ	SKIP_Z, r2, 0					// If we've reached the target position, don't touch the output
	LBCO	r8, CONST_PRUSHAREDRAM, 36, 4	// If we're updaing the output, reload the hold time for the next cycle
	XOR		r30, r30, 1<<7					// Toggle the step pin
	QBBC	SKIP_Z, r30.t7					// If step pin is low, don't increment step counters
	SUB		r2,	r2, 1						// Decrement steps remaining
	LBCO	r10, CONST_PRUSHAREDRAM, 12, 4	// Update current step position in shared memory
	QBBC	UPDATE_Z_ADD, r30.t5
	QBBS	UPDATE_Z_SUB, r30.t5
UPDATE_Z_ADD:
	ADD		r10, r10, 1
	SBCO	r10, CONST_PRUSHAREDRAM, 12, 4
	JMP		SKIP_Z
UPDATE_Z_SUB:
	SUB		r10, r10, 1
	SBCO	r10, CONST_PRUSHAREDRAM, 12, 4
SKIP_Z:

	OR		r9, r0, r1						// Bitwise OR all the step counters to see if anything is left to be done
	OR		r9, r9, r2
	QBNE	LOOP1, r9, 0					// While there is still work to be done, keep looping
	
	CALL	RUN								// Once all counters have hit zero, go back to the start and wait for new command
	
	HALT									// Halt the processor (although we will never get here...)
	