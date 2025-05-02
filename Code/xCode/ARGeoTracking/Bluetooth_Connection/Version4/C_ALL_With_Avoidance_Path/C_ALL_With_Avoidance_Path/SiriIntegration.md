# Siri Integration for C_ALL Navigation App

This document explains how to set up and use Siri with the C_ALL navigation app.

## Setup Instructions

After implementing the code changes, you will need to:

1. Open the project in Xcode
2. Add the Siri capability:
   - Select your project in the Project Navigator
   - Select your app target
   - Go to the "Signing & Capabilities" tab
   - Click "+" and select "Siri"

3. Create the Intent Definition file:
   - In Xcode, create a new file (File > New > File)
   - Select "Intent Definition File"
   - Name it "NavigationIntents.intentdefinition"
   - Configure a custom intent:
     - Set the title to "Navigate to location"
     - Set the description to "Navigate to a specific address"
     - Add a parameter named "destination" of type "Location"
     
   - In the Shortcuts App section:
     - Verify that "destination" appears in the "Supported Combinations" list
     - App launching is automatically enabled when a parameter is added to Supported Combinations
     
   - In the Suggestions section:
     - Ensure "Supports background execution" is checked
     - You can optionally set a Default Image

## Using Siri with C_ALL

Once set up, users can:

1. Ask Siri to navigate to a destination:
   - "Hey Siri, navigate to 1001 Washington St, Hoboken using C_ALL"
   - "Hey Siri, open C_ALL and take me to Hoboken"

2. After using the app to navigate a few times, Siri Shortcuts will suggest personalized shortcuts based on usage patterns.

## How It Works

1. The user makes a request to Siri
2. Siri processes the location and launches the C_ALL app
3. The app receives the destination information from Siri
4. The app automatically sets up navigation to the requested destination

## Troubleshooting

- If Siri doesn't recognize "C_ALL" correctly, try spelling it out: "C ALL" or "C underscore ALL"
- Make sure Location Services and Siri are enabled in device settings
- If navigation doesn't start automatically, check that you've granted the app permission to use Siri and Location Services 