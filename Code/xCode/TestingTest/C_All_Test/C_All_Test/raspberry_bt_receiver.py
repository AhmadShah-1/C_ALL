import dbus
from bluez_peripheral.gatt.service import Service
from bluez_peripheral.gatt.characteristic import characteristic, CharacteristicFlags as Flags
from bluez_peripheral.util import get_message_bus, Adapter
import asyncio
from bluez_peripheral.advert import Advertisement
from bluez_peripheral.agent import NoIoAgent
import logging
import signal

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class NumberReceiverService(Service):
    SERVICE_UUID = "12345678-1234-5678-1234-56789abcdef0"

    def __init__(self):
        super().__init__(self.SERVICE_UUID, True)
        self._value = bytearray()
        self._connected = False
        logger.info("NumberReceiverService initialized")

    # The characteristic now uses a signature that accepts two parameters: data and opts.
    # When data is None, it indicates a read request.
    @characteristic("12345678-1234-5678-1234-56789abcdef1", Flags.READ | Flags.WRITE)
    def number_characteristic(self, data, opts):
        if data is None:
            logger.debug("Read request received")
            return self._value
        try:
            number_str = data.decode('utf-8').strip()
            number = int(number_str)
            self._value = data
            logger.info(f"Received number: {number}")
            logger.debug(f"Raw value received: {data}")
            return True
        except ValueError as ve:
            logger.error(f"Invalid number format: {ve}")
            return False
        except Exception as e:
            logger.error(f"Error processing data: {e}")
            logger.error(f"Raw data received: {data}")
            return False

# Assign the setter function for the characteristic.
NumberReceiverService.number_characteristic.setter_func = NumberReceiverService.number_characteristic

class BLEServer:
    def __init__(self):
        self.service = None
        self.advertisement = None
        self.adapter = None
        self.bus = None
        self._running = True

    async def setup(self):
        try:
            # Initialize the D-Bus message bus
            self.bus = await get_message_bus()
            logger.info("D-Bus message bus initialized")
            
            # Create and register the Bluetooth agent
            agent = NoIoAgent()
            await agent.register(self.bus)
            logger.info("Bluetooth agent registered")
            
            # Get the first available Bluetooth adapter
            self.adapter = await Adapter.get_first(self.bus)
            if not self.adapter:
                raise Exception("No Bluetooth adapter found")
            logger.info("Bluetooth adapter found")
            
            # Ensure the adapter is powered on
            await self.adapter.set_powered(True)
            logger.info("Bluetooth adapter powered on")
            
            # Create and register the BLE service
            self.service = NumberReceiverService()
            await self.service.register(self.bus)
            logger.info("BLE service registered")
            
            # Create an advertisement for the service
            self.advertisement = Advertisement(
                localName="raspberrypi",
                serviceUUIDs=[NumberReceiverService.SERVICE_UUID],
                appearance=0x0000,
                timeout=0
            )
            
            # Register the advertisement with the adapter
            await self.advertisement.register(self.bus, self.adapter)
            logger.info("Advertisement registered")
            
            logger.info("BLE Server setup complete")
            logger.info("Waiting for connections... (Press Ctrl+C to stop)")
            
        except Exception as e:
            logger.error(f"Error during setup: {e}")
            raise

    def stop(self):
        self._running = False
        logger.info("Server stopping...")

async def main():
    try:
        server = BLEServer()
        
        # Setup signal handlers to gracefully stop the server
        loop = asyncio.get_event_loop()
        loop.add_signal_handler(signal.SIGINT, server.stop)
        loop.add_signal_handler(signal.SIGTERM, server.stop)
        
        await server.setup()
        
        # Keep the server running until a stop signal is received
        while server._running:
            await asyncio.sleep(1)
            
    except Exception as e:
        logger.error(f"Error in main: {e}")
        raise
    finally:
        logger.info("Server shutdown complete")

if __name__ == '__main__':
    asyncio.run(main())
