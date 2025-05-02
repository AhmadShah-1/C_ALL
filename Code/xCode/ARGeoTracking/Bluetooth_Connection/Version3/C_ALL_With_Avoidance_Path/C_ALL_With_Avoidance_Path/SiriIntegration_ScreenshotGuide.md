# Visual Guide for Siri Integration Setup

This document provides visual guidance for setting up Siri integration in your C_ALL navigation app.

## 1. Adding Siri Capability

In Xcode, select your project in the project navigator, then select your app target and go to the "Signing & Capabilities" tab:

```
+---------------------------------------------+
|                                             |
|  [Project Navigator]    [App Target]        |
|                                             |
|  +------------------+  +------------------+ |
|  | C_ALL_With_Avoid |  | General          | |
|  +------------------+  | Signing & Cap ◀︎ | |
|                        | Info             | |
|                        +------------------+ |
|                                             |
|  [+ Button]                                 |
|  +-------+                                  |
|  |   +   |  ← Click to add capability       |
|  +-------+                                  |
|                                             |
+---------------------------------------------+
```

Select "Siri" from the capabilities list:

```
+---------------------------------------------+
|                                             |
|  +-----------------------+                  |
|  | Add Capability        |                  |
|  +-----------------------+                  |
|  | ○ App Groups          |                  |
|  | ○ Associated Domains  |                  |
|  | ○ Background Modes    |                  |
|  | ...                   |                  |
|  | ○ Sign In with Apple  |                  |
|  | ● Siri ◀︎             |                  |
|  | ○ Speech Recognition  |                  |
|  | ...                   |                  |
|  +-----------------------+                  |
|                                             |
+---------------------------------------------+
```

## 2. Creating Intent Definition File

Create a new file by selecting File > New > File in Xcode, then select "Intent Definition File":

```
+---------------------------------------------+
|                                             |
|  +-----------------------+                  |
|  | Choose a template     |                  |
|  +-----------------------+                  |
|  | iOS                   |                  |
|  |   Source              |                  |
|  |     Swift File        |                  |
|  |     Header File       |                  |
|  |     ...               |                  |
|  |   Resources           |                  |
|  |     PropertyList      |                  |
|  |     Intent Definition ◀︎                 |
|  |     ...               |                  |
|  +-----------------------+                  |
|                                             |
+---------------------------------------------+
```

## 3. Configuring the Intent

After creating the file, you'll see the intent editor with these main sections:

```
+---------------------------------------------+
|                                             |
|  [Intent Editor]                            |
|  - Custom Intent                            |
|  - Parameters                               |
|  - Shortcuts App                            |
|  - Suggestions                              |
|                                             |
+---------------------------------------------+
```

Configure the "Custom Intent" section first:

```
+---------------------------------------------+
|                                             |
|  [Custom Intent]                            |
|                                             |
|  Title: Navigate To Location Intent         |
|  Description: Navigate to a specific address|
|                                             |
|  Category: [ Generic        ▼ ]             |
|                                             |
+---------------------------------------------+
```

Then add a parameter in the "Parameters" section:

```
+---------------------------------------------+
|                                             |
|  [Parameters]                               |
|  +---------------------------------+        |
|  | + Add Parameter                 |        |
|  +---------------------------------+        |
|                                             |
|  Name: destination                          |
|  Display Name: Destination                  |
|  Type: [ Location/Placemark    ▼ ]          |
|                                             |
+---------------------------------------------+
```

## 4. Configuring Shortcuts App Section

In the "Shortcuts App" section, you'll see:

```
+---------------------------------------------+
|                                             |
|  [Shortcuts App]                            |
|                                             |
|  Input Parameter: [ None ▼ ]                |
|                                             |
|  Key Parameter: [ None ▼ ]                  |
|                                             |
|  Supported Combinations:                    |
|  | destination                              |
|  |                                          |
|  +------------------------------------------+
|                                             |
|  Preview:                                   |
|  +------------------------------------------+
|  |                                          |
|  |  APP NAME                                |
|  |  Summary                                 |
|  |                                          |
|  |  More Options                            |
|  |  Destination                             |
|  |                                          |
|  +------------------------------------------+
|                                             |
+---------------------------------------------+
```

The presence of "destination" in Supported Combinations enables app launching with this parameter. This is already correctly configured.

## 5. Configuring Suggestions Section

In the "Suggestions" section:

```
+---------------------------------------------+
|                                             |
|  [Suggestions]                              |
|                                             |
|  Default Image: [ None ▼ ]                  |
|                                             |
|  Supported Combinations:                    |
|  | destination                              |
|  |                                          |
|  +------------------------------------------+
|                                             |
|  Summary: [                              ]  |
|                                             |
|  Description: [                          ]  |
|                                             |
|  Background: ☑ Supports background execution|
|                                             |
+---------------------------------------------+
```

The "Supports background execution" checkbox is already checked, which is good. This allows Siri to handle the intent.

## 6. Testing Siri Integration

Your intent is already correctly configured for app launching. To test the integration:

1. Build and run your app on a device
2. Use the app normally to navigate to some destinations
3. Ask Siri: "Hey Siri, navigate to 1001 Washington St, Hoboken using C_ALL"
4. Siri should confirm and then launch your app with the destination pre-set

```
+---------------------------------------------+
|                                             |
|  [Siri Interface]                           |
|                                             |
|  "Navigate to 1001 Washington St,           |
|   Hoboken using C_ALL"                      |
|                                             |
|  Navigate to 1001 Washington St,            |
|  Hoboken, NJ using C_ALL?                   |
|                                             |
|  [Confirm]    [Cancel]                      |
|                                             |
+---------------------------------------------+ 
```
