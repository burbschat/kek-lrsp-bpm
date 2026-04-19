import rogue.interfaces.stream as ris
import pyrogue as pr

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

        # Not saving config/state to YAML
        guiGroups = ['NoStream','NoState','NoConfig']

        # Remove data variable from stream and server
        self.Data.addToGroup('NoServe')
        self.Data.addToGroup('NoStream')
        self.Data.addToGroup('NoStatus')

    def _start(self):
        super()._start()
        self.RxEnable.set(value=True)

    # Method which is called when a frame is received
    def process(self,frame):
        with self.root.updateGroup():
            pr.DataReceiver.process(self,frame)

            print(self.Data.value())
