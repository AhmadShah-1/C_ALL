import bluetooth
from bluetooth import *
import time
import sys
import os

def setup_bluetooth_server():
    try:
        # Make device discoverable
        os.system("bluetoothctl discoverable on")
        
        server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
        server_sock.bind(("", PORT_ANY))
        server_sock.listen(1)

        port = server_sock.getsockname()[1]

        uuid = "00001101-0000-1000-8000-00805F9B34FB"

        advertise_service(server_sock, "RaspberryPiSerial",
                        service_id=uuid,
                        service_classes=[uuid, SERIAL_PORT_CLASS],
                        profiles=[SERIAL_PORT_PROFILE],
                        provider="RaspberryPi",
                        description="Serial communication service")

        print(f"Waiting for connection on RFCOMM channel {port}")
        print(f"Service UUID: {uuid}")
        return server_sock
    except Exception as e:
        print(f"Error setting up Bluetooth server: {str(e)}")
        sys.exit(1)

def main():
    server_sock = setup_bluetooth_server()
    
    while True:
        try:
            print("\nWaiting for incoming connection...")
            client_sock, client_info = server_sock.accept()
            print(f"Accepted connection from {client_info}")

            while True:
                try:
                    data = client_sock.recv(1024)
                    if not data:
                        print("Connection lost, waiting for new connection...")
                        break
                    
                    received_str = data.decode('utf-8')
                    print(f"Received: {received_str}")
                    
                    # Try to convert to number if possible
                    try:
                        number = int(received_str)
                        print(f"Converted to number: {number}")
                        # Here you can process the received number for your program
                    except ValueError:
                        print(f"Received data is not a valid number: {received_str}")
                
                except IOError as e:
                    print(f"Error receiving data: {str(e)}")
                    break
                    
        except IOError as e:
            print(f"Connection error: {str(e)}")
            client_sock.close()
            continue
            
        except KeyboardInterrupt:
            print("\nDisconnecting...")
            if 'client_sock' in locals():
                client_sock.close()
            server_sock.close()
            print("Goodbye!")
            break
            
        except Exception as e:
            print(f"Unexpected error: {str(e)}")
            if 'client_sock' in locals():
                client_sock.close()
            continue

if __name__ == "__main__":
    main() 