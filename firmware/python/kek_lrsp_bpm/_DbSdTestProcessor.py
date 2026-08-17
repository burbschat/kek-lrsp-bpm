import rogue.interfaces.stream as ris
import pyrogue as pr
import numpy as np

import rogue
rogue.Version.minVersion('6.2.0')

# Class for streaming RX
class DbSdTestProcessor(pr.DataReceiver):
    # Init method must call the parent class init
    def __init__( self,
            hidden      = False,
            **kwargs):
        pr.Device.__init__(self, hidden=hidden, **kwargs)
        ris.Slave.__init__(self)
        pr.DataReceiver.__init__(self, enableOnStart=True, hideData=True, hidden=hidden, **kwargs)

        self.add(
            pr.LocalVariable(
                name="DataValues",
                description="Decoded buffer data values",
                typeStr="UInt16[np]",
                value=0,
                typeCheck=False,
                hidden=False,
            )
        )


    def _start(self):
        super()._start()
        self.RxEnable.set(value=True)

    # Method which is called when a frame is received
    def process(self,frame):
        with self.root.updateGroup():
            pr.DataReceiver.process(self,frame)

            # OMFG THE DATA IS BIG ENDIAN UINT16? WHY.
            data_values = self.Data.value().view('>u2')
            self.DataValues.set(data_values, write=True)
            print(data_values)
            print(data_values.shape)
