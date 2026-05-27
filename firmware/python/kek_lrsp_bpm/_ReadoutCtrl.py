import pyrogue as pr

# Trig sources enum example:
# trigSourcesEnum = {
#     0x0: 'irigTrig',
#     0x1: 'irigComp',
#     0x2: 'evr',
# }

class ReadoutCtrl(pr.Device):
    def __init__(self, trigSourcesEnum, **kwargs):
        super().__init__(**kwargs)

        self._trigSourcesEnum = trigSourcesEnum

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
            units        = '1/254.5MHz',
        ))

        self.add(pr.LinkVariable(
            name         = "TrigRingBufDly",
            description  = "TrigRingBufDly in microseconds",
            mode         = "RW",
            units        = "microsec",
            disp         = '{:0.3f}',
            dependencies = [self.TrigRingBufDlyRaw],
            linkedGet    = lambda: (float(self.TrigRingBufDlyRaw.value()+1) * (1.0/254.5)),
            linkedSet    = lambda value, write: self.TrigRingBufDlyRaw.set(int(value/(1.0/254.5))-1),
        ))

        self.add(pr.RemoteVariable(
            name         = "deglitchLenRaw",
            description  = "Duration for which trigger input must be low to be recognized as low",
            offset       = 0x30,
            bitSize      = 12,
            mode         = "RW",
            units        = '1/254.5MHz',
        ))

        self.add(pr.RemoteVariable(
            name         = 'stateReg',
            description  = 'Register indicating the state of the trigger FSM',
            offset       = 0x34,
            bitSize      = 8,
            mode         = 'RO',
            pollInterval = 1,
            # These are encoding dependent and thus may depend on implementation of enums in the firmware
            enum        = {
                0x0: 'IDLE',
                0x1: 'ARMED',
                0x2: 'DELAY',
                0x3: 'DEGLITCH',
            },
        ))
