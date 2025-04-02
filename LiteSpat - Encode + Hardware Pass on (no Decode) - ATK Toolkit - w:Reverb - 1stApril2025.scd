////////////////////////////////////////////////////////////////////////////////////////
// Basic settings for this script
////////////////////////////////////////////////////////////////////////////////////////

// port for listening to incoming OSC data
~osc_IN = 6666;

// this determines how many sources (and inputs) we have
~n_inputs = 32;

// Using 5th order HOA with ATK
~hoa_order = 5;
~n_hoa_channels = (pow(~hoa_order + 1.0, 2.0)).asInteger; // (n+1)^2 = 36 channels

////////////////////////////////////////////////////////////////////////////////////////
// Server options
////////////////////////////////////////////////////////////////////////////////////////

s.options.device = "litespat2";
s.options.numInputBusChannels = ~n_inputs;
s.options.numOutputBusChannels = ~n_hoa_channels;
s.options.memSize = 65536;
s.options.numBuffers = 1024;
s.options.numWireBufs = 128;  // Default is 64, increase this value
s.options.maxNodes = 2048;     // Increase number of available nodes

////////////////////////////////////////////////////////////////////////////////////////
// Start of main routine for setting up the spatial renderer
////////////////////////////////////////////////////////////////////////////////////////

// Load ATK-HOA extensions if not already loaded. You may need to install this extension first:

//Step 1 -
//Quarks.install("https://github.com/florian-grond/SC-HOA")

//Step 2 -

/*(

Atk.downloadKernels;
Atk.downloadMatrices;
Atk.downloadSounds;

)*/


s.waitForBoot({

    s.sync;

    // Create an input group
    ~input_GROUP = Group.new;
    s.sync;

    ////////////////////////////////////////////////////////////////////////////////////
    // This is the SynthDef for the HOA encoders with ATK

    SynthDef(\hoa_atk_encoder,
        {
            |
            in_bus = nil,
            out_bus = 0,
            azim = 0,
            elev = 0,
            dist = 0.1,
            gain = 1
            |

            var sound = gain * SoundIn.ar(in_bus);
            var level = (1.0/(dist+1.0))*(1.0 / (max(0.01,dist)+1.0));

            // Create HOA encoder using ATK
			var encoder = HoaEncodeDirection.ar(sound * level, (azim * (pi/180)) , elev, ~hoa_order);

            Out.ar(out_bus, encoder);

    }).add;

    ////////////////////////////////////////////////////////////////////////////////////////
    // use server sync after asynchronous commands

    s.sync;

    ////////////////////////////////////////////////////////////////////////////////////////
    // The group for the spatial encoders

    ~spatial_GROUP = Group.after(~input_GROUP);

    s.sync;

    ////////////////////////////////////////////////////////////////////////////////////////
    // a multichannel audio bus for the encoded Ambisonics signal

    ~ambi_BUS = Bus.audio(s, ~n_hoa_channels);

    // Create a dedicated bus for reverb
    ~reverb_BUS = Bus.audio(s, ~n_hoa_channels);

    ////////////////////////////////////////////////////////////////////////////////////////
    // create all encoders in a loop

    ~hoa_panners = [];

    for (0, ~n_inputs-1, {arg i;
        post('Adding HOA ATK encoder module: ');
        i.postln;

        // this is the array of encoders

        ~hoa_panners = ~hoa_panners.add(
            Synth(\hoa_atk_encoder,
                [
                    \in_bus, i,
                    \out_bus, ~ambi_BUS.index
                ],
                target: ~spatial_GROUP
            )
        );
    });
    s.sync;

    ////////////////////////////////////////////////////////////////////////////////////////
    // Create a group for effects processing
    ////////////////////////////////////////////////////////////////////////////////////////

    ~effects_GROUP = Group.after(~spatial_GROUP);

    s.sync;

    ////////////////////////////////////////////////////////////////////////////////////////
    // Define and create the reverb processor
    ////////////////////////////////////////////////////////////////////////////////////////

    SynthDef(\reverb_processor, {
        |
        in_bus,
        out_bus,
        mix = 0.2, // Full wet signal for the reverb bus
        room = 0.05,
        damp = 0.8
        |

        var in_signal = In.ar(in_bus, ~n_hoa_channels);
        var reverb = FreeVerb.ar(in_signal, mix: mix, room: room, damp: damp);

        Out.ar(out_bus, reverb);
    }).add;
    s.sync;

    // Create the reverb processor
    ~reverb_processor = Synth(\reverb_processor, [
        \in_bus, ~ambi_BUS.index,
        \out_bus, ~reverb_BUS.index
    ], target: ~effects_GROUP);
    s.sync;

    ////////////////////////////////////////////////////////////////////////////////////////
    // Another group for the outputs
    ////////////////////////////////////////////////////////////////////////////////////////

    ~output_GROUP = Group.after(~effects_GROUP);
    s.sync;

    ////////////////////////////////////////////////////////////////////////////////////////
    // The output node - using ATK HOA decoding
    ////////////////////////////////////////////////////////////////////////////////////////

    // Define a HOA decoder SynthDef
    SynthDef(\hoa_atk_decoder, {
        |
        gain = 0.8,
        dry_wet_mix = 0.01
        |

        // Read dry multichannel ambisonic signal
        var dry_signal = In.ar(~ambi_BUS.index, ~n_hoa_channels);


        // Read wet (reverb) multichannel ambisonic signal
        var wet_signal = In.ar(~reverb_BUS.index, ~n_hoa_channels);

        // Mix dry and wet signals
        var output_signal = (dry_signal * (1-dry_wet_mix)) + (wet_signal * dry_wet_mix);

        Out.ar(0, gain * output_signal);
    }).add;

    s.sync;

    ~hoa_output = Synth(\hoa_atk_decoder, target: ~output_GROUP);

	s.sync;

    ////////////////////////////////////////////////////////////////////////////////////////
    // OSC listener functions for TouchDesigner messages
    ////////////////////////////////////////////////////////////////////////////////////////

    // For azimuth control
    OSCdef(\azimuth,
        {
            arg msg, time, addr, recvPort;
            var sourceID = msg[1];
            var azim = msg[2];

            if(sourceID < ~n_inputs, {
                ~hoa_panners[sourceID].set(\azim, azim);
                postln("Source " ++ sourceID ++ " Azimuth: " ++ azim);
            });
        },
    '/source/azim');

    // For elevation control
    OSCdef(\elevation,
        {
            arg msg, time, addr, recvPort;
            var sourceID = msg[1];
            var elev = msg[2];

            if(sourceID < ~n_inputs, {
                ~hoa_panners[sourceID].set(\elev, elev);
                postln("Source " ++ sourceID ++ " Elevation: " ++ elev);
            });
        },
    '/source/elev');

    // For distance control
    OSCdef(\distance,
        {
            arg msg, time, addr, recvPort;
            var sourceID = msg[1];
            var dist = msg[2];

            if(sourceID < ~n_inputs, {
                ~hoa_panners[sourceID].set(\dist, dist);
                postln("Source " ++ sourceID ++ " Distance: " ++ dist);
            });
        },
    '/source/dist');

    // For gain control
    OSCdef(\gain,
        {
            arg msg, time, addr, recvPort;
            var sourceID = msg[1];
            var gain = msg[2];

            if(sourceID < ~n_inputs, {
                ~hoa_panners[sourceID].set(\gain, gain);
                postln("Source " ++ sourceID ++ " Gain: " ++ gain);
            });
        },
    '/source/gain');

    // For controlling multiple parameters at once
    OSCdef(\source_xyz,
        {
            arg msg, time, addr, recvPort;
            var sourceID = msg[1];
            var azim = msg[2];
            var elev = msg[3];
            var dist = msg[4];

            if(sourceID < ~n_inputs, {
                ~hoa_panners[sourceID].set(\azim, azim);
                ~hoa_panners[sourceID].set(\elev, elev);
                ~hoa_panners[sourceID].set(\dist, dist);
                postln("Source " ++ sourceID ++ " Position: azim=" ++ azim ++ ", elev=" ++ elev ++ ", dist=" ++ dist);
            });
        },
    '/source/xyz');

    // For controlling master output gain
    OSCdef(\master_gain,
        {
            arg msg, time, addr, recvPort;
            var gain = msg[1];

            ~hoa_output.set(\gain, gain);
            postln("Master gain: " ++ gain);
        },
    '/master/gain');

    // Set fixed reverb parameters
    // These can be adjusted manually in the code instead of via OSC
    ~hoa_output.set(\dry_wet_mix, 0.2);
    ~reverb_processor.set(\room, 0.8);
    ~reverb_processor.set(\damp, 0.5);

    postln("Reverb settings - Mix: 0.2, Room: 0.8, Damp: 0.5");

    // open our extra ports for OSC and give feedback
    thisProcess.openUDPPort(~osc_IN);
    postln("Listening for OSC on ports: "++thisProcess.openPorts);

	    // Display server meters
    s.meter;

    // Print info about the routing and buses
    postln("HOA Spatial Audio System Ready:");
    postln("- Number of inputs: " ++ ~n_inputs);
    postln("- Number of HOA channels: " ++ ~n_hoa_channels);
    postln("- Ambisonic bus index: " ++ ~ambi_BUS.index);
    postln("- Reverb bus index: " ++ ~reverb_BUS.index);
});