import time
import pigpio
import asyncio
import signal
import logging
import dbus
from bluez_peripheral.gatt.service import Service
from bluez_peripheral.gatt.characteristic import characteristic, CharacteristicFlags as Flags
from bluez_peripheral.util import get_message_bus, Adapter
from bluez_peripheral.advert import Advertisement
from bluez_peripheral.agent import NoIoAgent

# === Servo Configuration and Functions ===

# GPIO pin for the servo signal
SERVO_PIN = 17  # Adjust as needed

# Servo PWM parameters (adjust if necessary)
SERVO_MIN_PULSE = 1000  # microseconds
SERVO_MAX_PULSE = 2000  # microseconds
STOP_PULSE = 1500       # neutral pulse width

# Time (in seconds) to move 60 degrees (from spec)
TIME_PER_60_DEG = 0.119

# Initialize pigpio
pi = pigpio.pi()
if not pi.connected:
    exit("Could not connect to pigpio daemon.")

def rotate_servo(degrees):
    """
    Rotates a continuous rotation servo by the given number of degrees.
    Positive degrees rotate clockwise, negative degrees rotate counterclockwise.
    """
    if degrees == 0:
        pi.set_servo_pulsewidth(SERVO_PIN, STOP_PULSE)
        return

    direction = 1 if degrees > 0 else -1
    pulse_width = SERVO_MAX_PULSE if direction == 1 else SERVO_MIN_PULSE

    # Calculate the time needed for the given degree of rotation.
    time_needed = abs(degrees) * (TIME_PER_60_DEG / 60)

    # Activate rotation and wait for the computed duration.
    pi.set_servo_pulsewidth(SERVO_PIN, pulse_width)
    time.sleep(time_needed)
    pi.set_servo_pulsewidth(SERVO_PIN, STOP_PULSE)
    print(f"Rotated {degrees} degrees.")

# === BLE Service Definitions ===

logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class NumberReceiverService(Service):
    SERVICE_UUID = "12345678-1234-5678-1234-56789abcdef0"

    def __init__(self, loop):
        super().__init__(self.SERVICE_UUID, True)
        self._value = bytearray()
        self.loop = loop
        logger.info("NumberReceiverService initialized")

    @characteristic("12345678-1234-5678-1234-56789abcdef1", Flags.READ | Flags.WRITE)
    def number_characteristic(self, *args, **kwargs):
        # The read behavior simply returns the last received value.
        return self._value

    def _set_number(self, data, opts):
        """
        Called when a write is received on the characteristic.
        Expects a UTF-8 encoded integer representing degrees.
        """
        if data is None:
            logger.debug("Read request received.")
            return self._value

        try:
            number_str = data.decode('utf-8').strip()
            degrees = int(number_str)
            self._value = data
            logger.info(f"Received number: {degrees}")
            logger.debug(f"Raw value received: {data}")

            # Offload servo rotation to a separate thread so the BLE event loop isn't blocked.
            self.loop.run_in_executor(None, rotate_servo, degrees)
            return True
        except ValueError as ve:
            logger.error(f"Invalid number format: {ve}")
            return False
        except Exception as e:
            logger.error(f"Error processing data: {e}")
            logger.error(f"Raw data received: {data}")
            return False

# Set the setter function for the characteristic.
NumberReceiverService.number_characteristic.setter_func = lambda service, data, opts: service._set_number(data, opts)

class BLEServer:
    def __init__(self, loop):
        self.service = None
        self.advertisement = None
        self.adapter = None
        self.bus = None
        self._running = True
        self.loop = loop

    async def setup(self):
        try:
            # Initialize the D-Bus message bus.
            self.bus = await get_message_bus()
            logger.info("D-Bus message bus initialized")

            # Register the Bluetooth agent.
            agent = NoIoAgent()
            await agent.register(self.bus)
            logger.info("Bluetooth agent registered")

            # Get the first available Bluetooth adapter.
            self.adapter = await Adapter.get_first(self.bus)
            if not self.adapter:
                raise Exception("No Bluetooth adapter found")
            logger.info("Bluetooth adapter found")

            # Ensure the adapter is powered on.
            await self.adapter.set_powered(True)
            logger.info("Bluetooth adapter powered on")

            # Create and register the BLE service.
            self.service = NumberReceiverService(self.loop)
            await self.service.register(self.bus)
            logger.info("BLE service registered")

            # Create and register an advertisement.
            self.advertisement = Advertisement(
                localName="raspberrypi",
                serviceUUIDs=[NumberReceiverService.SERVICE_UUID],
                appearance=0x0000,
                timeout=0
            )
            await self.advertisement.register(self.bus, self.adapter)
            logger.info("Advertisement registered")

            logger.info("BLE Server setup complete. Waiting for connections... (Press Ctrl+C to stop)")
        except Exception as e:
            logger.error(f"Error during setup: {e}")
            raise

    def stop(self):
        self._running = False
        logger.info("Server stopping...")

async def main():
    try:
        loop = asyncio.get_running_loop()
        server = BLEServer(loop)
        loop.add_signal_handler(signal.SIGINT, server.stop)
        loop.add_signal_handler(signal.SIGTERM, server.stop)

        await server.setup()

        # Run the server until a stop signal is received.
        while server._running:
            await asyncio.sleep(1)
    except Exception as e:
        logger.error(f"Error in main: {e}")
        raise
    finally:
        logger.info("Server shutdown complete")
        # Clean up the servo by stopping it and terminating the pigpio connection.
        pi.set_servo_pulsewidth(SERVO_PIN, STOP_PULSE)
        pi.stop()

if __name__ == '__main__':
    asyncio.run(main())
