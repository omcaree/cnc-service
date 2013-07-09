var pru = require('pru');

// Some useful constants
var STEPS_PER_REV = 400*16;		// Including microstepping
var MM_PER_REV = 0.7;			// Annoying fine M4 thread
var STEPS_PER_MM = STEPS_PER_REV / MM_PER_REV;
var NS_PER_CYCLE = 180;			// Approximate time (ns) per PRU code cycle

// Some random positions
var positions = [	[	0,		0,		0	],
					[	100,	0,		0	],
					[	100,	100,	0	],
					[	0,		100,	0	],
					[	0,		0,		0	],
					[	100,	100,	0	]];
					
var speed = 2;	//mm/sec

// Initialise the PRU
pru.init();

var i = 0;
var origin = new Array(3);

// Interrupt callback, called when PRU is ready for new command
var interrupt = function() {	
	// If this is first movement, get the default origin from PRU
	// Currently defaults to 0x7FFFFFFF (middle of unsigned int range)
	// as PRU code only handles unsigned ints
	if (i==0) {
		origin[0] = pru.getSharedRAMInt(1);
		origin[1] = pru.getSharedRAMInt(2);
		origin[2] = pru.getSharedRAMInt(3);
		i++;	// Skip first position as we'll assume its at 0,0,0
	} else {
		// How long did last movement take?
		var t_end = new Date().getTime();
		console.log("Took: " + (t_end - t_start).toFixed(2) + "ms");
	}
	
	// Update PRU position target (in steps)
	pru.setSharedRAMInt(4, origin[0] + positions[i][0] * STEPS_PER_MM);
	pru.setSharedRAMInt(5, origin[1] + positions[i][1] * STEPS_PER_MM);
	pru.setSharedRAMInt(6, origin[2] + positions[i][2] * STEPS_PER_MM);
	
	// Calculate distance increments
	var dx = positions[i][0] - positions[i-1][0];
	var dy = positions[i][1] - positions[i-1][1];
	var dz = positions[i][2] - positions[i-1][2];
	
	// Calculate speed scaling factor (Euclidian norm)
	var speed_scale = Math.sqrt(dx*dx+dy*dy+dz*dz);
	
	// Scale speed in each axis
	var sx = speed/speed_scale * Math.abs(dx);
	var sy = speed/speed_scale * Math.abs(dy);
	var sz = speed/speed_scale * Math.abs(dz);
	
	// Set (half) PWM period
	pru.setSharedRAMInt(7, 1/(sx * STEPS_PER_MM)/(NS_PER_CYCLE*1E-9)/2);
	pru.setSharedRAMInt(8, 1/(sy * STEPS_PER_MM)/(NS_PER_CYCLE*1E-9)/2);
	pru.setSharedRAMInt(9, 1/(sz * STEPS_PER_MM)/(NS_PER_CYCLE*1E-9)/2);
	
	i++;
	
	// Wait 1s before commencing next movement
	console.log("Waiting 1s");
	setTimeout(function() {
		// Start the PRU by zeroing status register
		pru.setSharedRAMInt(0,0);
		
		// Clear the interrupt so we can get another one
		pru.clearInterrupt();
		
		// Wait for next interrupt
		pru.waitForInterrupt(interrupt);
		t_start = new Date().getTime();
	},1000);
}

var t_start;

// Wait for first interrupt
pru.waitForInterrupt(interrupt);

// Keep track of whats going on at 10Hz
var x_last = 0;
var y_last = 0;
var z_last = 0;
var inter = setInterval(function() {
	// Calculate actual speed
	var x = (pru.getSharedRAMInt(1)-origin[0])/STEPS_PER_MM;
	var y = (pru.getSharedRAMInt(2)-origin[1])/STEPS_PER_MM;
	var z = (pru.getSharedRAMInt(3)-origin[2])/STEPS_PER_MM;
	var dx = x - x_last;
	var dy = y - y_last;
	var dz = z - z_last;
	x_last = x;
	y_last = y;
	z_last = z;
	var s = Math.sqrt(dx*dx + dy*dy + dz*dz)*10;

	// Print useful things
	console.log(x.toFixed(2) + "\t" + y.toFixed(2) + "\t" + z.toFixed(2) + "\t" + s.toFixed(1));

// Some old debugging
//	console.log(pru.getSharedRAMInt(10) + "\t" + pru.getSharedRAMInt(11) + "\t" + pru.getSharedRAMInt(12));
//	console.log((pru.getSharedRAMInt(10) | pru.getSharedRAMInt(11) | pru.getSharedRAMInt(12)) + " = " + pru.getSharedRAMInt(13));
}, 100);

// Start the PRU code
pru.execute("cnc.bin");
