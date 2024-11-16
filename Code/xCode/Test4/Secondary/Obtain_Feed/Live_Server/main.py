# main.py

import socket
import threading
import struct
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image
import io
import traceback

# Server Configuration
HOST = '0.0.0.0'  # Listen on all network interfaces
PORT = 12345      # Port number to listen on

def recvall(conn, n):
    """Helper function to receive n bytes or return None if EOF is hit."""
    data = b''
    while len(data) < n:
        packet = conn.recv(n - len(data))
        if not packet:
            return None
        data += packet
    return data

def receive_full_message(conn):
    """Receive a message prefixed with its length."""
    # First, receive the length of the message (4 bytes)
    raw_msglen = recvall(conn, 4)
    if not raw_msglen:
        return None
    msglen = struct.unpack('>I', raw_msglen)[0]
    # Now receive the message data
    return recvall(conn, msglen)

def start_server():
    plt.ion()  # Enable interactive mode
    fig, ax = plt.subplots()
    image_display = None

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server_socket:
        server_socket.bind((HOST, PORT))
        server_socket.listen()
        print(f"Server listening on {HOST}:{PORT}")

        conn, addr = server_socket.accept()
        with conn:
            print(f"Connected by {addr}")
            while True:
                try:
                    data = receive_full_message(conn)
                    if not data:
                        print("Connection closed by client.")
                        break
                    print(f"Received data of length: {len(data)} bytes")
                    if data == b'':
                        continue
                    try:
                        # Attempt to decode as UTF-8
                        message = data.decode('utf-8')
                        print(f"Decoded message: {message}")
                        if message == "Hello, Server!":
                            print("Received initial greeting.")
                        else:
                            print("Received unexpected text message.")
                    except UnicodeDecodeError:
                        # Assume the data is JPEG image data
                        print("Received image data.")
                        # Save the received data to a file for debugging
                        with open('received_image.jpg', 'wb') as f:
                            f.write(data)
                        print("Saved received image to 'received_image.jpg'")

                        try:
                            # Decode using PIL
                            image = Image.open(io.BytesIO(data))
                            print(f"Image size: {image.size}, mode: {image.mode}")

                            # Optionally, print pixel values
                            pixels = list(image.getdata())
                            print(f"First 10 pixels: {pixels[:10]}")

                            # Display the image using Matplotlib
                            ax.imshow(image)
                            ax.axis('off')  # Hide axis
                            plt.draw()
                            plt.pause(0.001)
                            ax.clear()
                        except Exception as e:
                            print("Exception while displaying image with Matplotlib:", e)
                            traceback.print_exc()
                except Exception as e:
                    print("Error:", e)
                    traceback.print_exc()
                    break
    plt.close(fig)

if __name__ == "__main__":
    threading.Thread(target=start_server).start()
