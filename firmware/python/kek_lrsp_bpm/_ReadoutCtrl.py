import pyrogue as pr
import time

class ReadoutCtrl(pr.Device):
    def __init__(self,
            sampleRate  = 0.0,
            ampDispProc = None,
            SSR         = 16,
        **kwargs):
        super().__init__(**kwargs)

        self.smplTime = 1/sampleRate
        self.ampDispProc = ampDispProc
        self._LiveDispTrigCnt = 0
        self._SSR = SSR

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

        # Put those back if required. Registers remain in hld but for now do nothing.
        # for i in range(4):
        #     self.add(pr.RemoteVariable(
        #         name         = f'FineDelay[{i}]',
        #         description  = 'Used to delay the AMP waveform after the SSR_DDC and before ring buffer',
        #         offset       = 0x14,
        #         bitSize      = 4,
        #         bitOffset    = 8*i,
        #         mode         = 'RW',
        #         units        = 'sample',
        #         # hidden       = True,
        #     ))
        #
        # for i in range(4):
        #     self.add(pr.RemoteVariable(
        #         name         = f'CoarseDelay[{i}]',
        #         description  = 'Used to delay the AMP waveform after the SSR_DDC and before ring buffer',
        #         offset       = 0x18,
        #         bitSize      = 4,
        #         bitOffset    = 8*i,
        #         mode         = 'RW',
        #         units        = f'{self._SSR} x sample',
        #         # hidden       = True,
        #     ))

        self.add(pr.RemoteVariable(
            name         = f'TrigInSelIdx',
            description  = f'Currently selected trigger source',
            offset       = 0x20,
            bitSize      = 2,
            bitOffset    = 16,
            enum         = {
                0x0: 'irigTrig',
                0x1: 'irigComp',
            },
        ))

        self.add(pr.RemoteVariable(
            name         = f'TrigInPolarity',
            description  = 'Sets the polarity of the fault signal',
            offset       = 0x20,
            bitSize      = 1,
            bitOffset    = 24,
            enum        = {
                0x0: 'NonInverted',
                0x1: 'Inverted',
            },
        ))

        self.add(pr.RemoteVariable(
            name         = 'TrigIn',
            description  = 'TrigIn = TrigInRaw xor TrigInPolarity',
            offset       = 0x24,
            bitSize      = 1,
            bitOffset    = 4,
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
