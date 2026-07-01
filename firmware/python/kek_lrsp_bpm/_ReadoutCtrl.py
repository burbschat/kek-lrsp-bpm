import pyrogue as pr

# Trig sources enum example:
# trigSourcesEnum = {
#     0x0: 'irigTrig',
#     0x1: 'irigComp',
#     0x2: 'evr',
# }

class ReadoutCtrl(pr.Device):
    def __init__(self, trigSourcesEnum, clkFreq, **kwargs):
        super().__init__(**kwargs)

        self._trigSourcesEnum = trigSourcesEnum
        # These are encoding dependent and thus may depend on implementation of enums in the firmware
        self._trigStatesEnum = {
                0x0: 'IDLE',
                0x1: 'ARMED',
                0x2: 'DELAY',
                0x3: 'DEGLITCH',
            }

        clkFreqMhz = clkFreq / 1e6

        self.add(pr.RemoteVariable(
            name         = 'NumTrigs',
            description  = 'Number of triggers supported by hardware module (depends on generic)',
            offset       = 0x00,
            bitSize      = 32,
            bitOffset    = 0,
            mode         = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'SwTrig',
            description  = 'Software ring buffer rigger',
            offset       = 0x4,
            bitSize      = 1,
            mode         = 'WO',
            hidden       = True,
        ))

        @self.command()
        def SendSwTrig():
            self.SwTrig.set(1)

        self.add(pr.RemoteVariable(
            name         = f'TrigInSelIdx',
            description  = f'Currently selected trigger source',
            offset       = 0x08,
            bitSize      = 4,
            bitOffset    = 0,
            enum         = self._trigSourcesEnum,
        ))

        self.add(pr.RemoteVariable(
            name         = f'TrigInPolarity',
            description  = 'Sets the polarity of the fault signal',
            offset       = 0x08,
            bitSize      = 1,
            bitOffset    = 4,
            enum        = {
                0x0: 'NonInverted',
                0x1: 'Inverted',
            },
        ))

        self.add(pr.RemoteVariable(
            name         = 'TrigsIn',
            description  = 'Bits indicating current state of available trigger signals',
            offset       = 0x20,
            bitSize      = 32,  # Maximally 32 bits but can read 32 always with unused ones being zero
            bitOffset    = 0,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'TrigInSel',
            description  = 'TrigIn = TrigInRaw xor TrigInPolarity',
            offset       = 0x24,
            bitSize      = 1,
            bitOffset    = 0,
            mode         = 'RO',
            pollInterval = 1,
        ))

        self.add(pr.RemoteVariable(
            name         = 'TrigInArm',
            description  = 'Arms the fault trigger',
            offset       = 0x28,
            bitSize      = 1,
            mode         = 'WO',
        ))

        self.add(pr.RemoteVariable(
            name         = 'SetKeepArm',
            description  = 'Keep FaultTrigReady = 1',
            offset       = 0x28,
            bitSize      = 1,
            bitOffset    = 2,
            mode         = 'WO',
        ))

        self.add(pr.RemoteVariable(
            name         = "TrigRingBufDlyRaw",
            description  = "Sets a delay between trigger detection and stopping the ring buffer",
            offset       = 0x2C,
            bitSize      = 24,
            mode         = "RW",
            units        = f"+1 {1/clkFreqMhz:.3g} us",
        ))

        self.add(pr.LinkVariable(
            name         = "TrigRingBufDly",
            description  = "TrigRingBufDly in microseconds",
            mode         = "RW",
            units        = "us",
            disp         = '{:0.5g}',
            dependencies = [self.TrigRingBufDlyRaw],
            # Note that raw value 0 means one delay cycle due to the FSM implementation
            linkedGet    = lambda: (float(self.TrigRingBufDlyRaw.value()+1) * (1.0/clkFreqMhz)),
            linkedSet    = lambda value, write: self.TrigRingBufDlyRaw.set(int(value/(1.0/clkFreqMhz))-1),
        ))

        self.add(pr.RemoteVariable(
            name         = "deglitchLenRaw",
            description  = "Duration for which trigger input must be low to be recognized as low",
            offset       = 0x30,
            bitSize      = 12,
            mode         = "RW",
            units        = f"{1/clkFreqMhz:.3g} us",
        ))

        self.add(pr.LinkVariable(
            name         = "deglitchLen",
            description  = "deglitchLen in microseconds",
            mode         = "RW",
            units        = "us",
            disp         = '{:0.5g}',
            dependencies = [self.deglitchLenRaw],
            # Technically here also there may be one cycle more when entering
            # the DEGLITCH state not when we already are in that state but we
            # don't really care.
            linkedGet    = lambda: (float(self.deglitchLenRaw.value()) * (1.0/clkFreqMhz)),
            linkedSet    = lambda value, write: self.deglitchLenRaw.set(int(value/(1.0/clkFreqMhz))),
        ))

        self.add(pr.RemoteVariable(
            name         = 'stateReg',
            description  = 'Register indicating the state of the trigger FSM',
            offset       = 0x34,
            bitSize      = 8,
            mode         = 'RO',
            pollInterval = 1,
            enum        = self._trigStatesEnum,
        ))

        # Publish state name as string for use in PyDM displays
        self.add(pr.LinkVariable(
            name         = "stateStr",
            description  = "String indicating the current state",
            mode         = "RO",
            dependencies = [self.stateReg],
            linkedGet    = lambda: self.getStateString(self.stateReg.value()),
        ))

    def getStateString(self, stateIdx):
        if stateIdx in self._trigStatesEnum:
            return self._trigStatesEnum[stateIdx]
        else:
            return "UNDEFINED"
