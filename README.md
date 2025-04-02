# LiteSpat-v2
Real time input audio ambisonic encoding plus spatialising parameter control via OSC using SuperCollider and IEM AIIIRA Decoder.

## What does it do and how does it work? 

LiteSpat is a simple SuperCollider script that listens to the incoming audio from your specified source, encodes it into 5th order ambisonics, and outputs the encoded bformat audio in 36 channels \[(order+1)^2 num of channels\] which is then passed on to an ambisonic decoding 36-channel buss in Repear with the IEM AIIRA Decoder plugin on it (for MAC OS). 

Alternatively, Jack Audio Connect Kit can be used in systems running Linux to directly open system audio, supercollider server and IEM AIIRA Decoder in Jack. 

