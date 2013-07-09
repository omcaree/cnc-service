CNC web service
===============

This is my attempt at designing an internet controlled CNC machine based around the BeagleBoneBlack (BBB), Node.JS and the BBB PRUs. This project started as a learning exercise and has slowly grown in to something which slightly works, so I'm not claiming it's particularly good. It is all still very much a work in progress so any comments/suggestions/criticism is welcomed!

I have written a basic Node.JS module to interact with the BBB PRU system (see [here](https://github.com/omcaree/node-pru)), which forms the basis of this project. To use this code you'll need to follow the set up instructions there, to get the PRU systems up and running and talking to node.

I have written some PRU assembly code for driving 3 stepper motors (X, Y, Z) using the conventional Step and Direction signals. Have a look at the source (or ask me) for details. To compile this code (assuming you've got your PRU system set up), simple type:

	pasm -b cnc.p
	
So far I have only been working on software (with some steppers just sitting on my desk), so the main code currently just drives them to arbitrary locations. You can see this for yourself with:

	node main.js
	
I wouldn't recommended running it on an actual CNC machine yet, as it'll probably break something (do so at your own risk!).