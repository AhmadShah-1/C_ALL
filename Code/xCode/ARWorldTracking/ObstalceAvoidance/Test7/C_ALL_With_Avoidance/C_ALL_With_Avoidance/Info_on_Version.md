# Info_on_Version



## Overview
This version focuses on a base implementation of changing the direction of the walking path (Does not include sidewalk recognition)



#### C_ALL_With_PathApp:
Is the entry into the app, it initializes the app and sets the stage for the view by referencing ContentView. It also informs the user if their device is supported by the program (Only the AR feature)

#### ContentView: 
This file displays the inital actual view of the app (essentially the AR View with the minimap)

#### ARWrapper:
This file creates the entire ARView for the app, including the UI View, AR View (AR World Creation), sets camera access and location permissions, and the logic for the obstacle avoidance

#### Coordinator:
This is a class present in ARWrapper where all the permissions are used and calculations done, as well as displaying the path, this file is critical to the function of obstacle avoidance as the center of this version

Note: The bulk of ARWrapper is the Coordinator class, with the other external functions (in this file) meant to be utilized only by Coordinator. 


#### CompassView:
Provides a view to display a compass of the current heading (only used for testing, as path was oriented incorrectly and was used for debugging). 
Note: Originally was used by ARWrapper, but was removed after testing was completed. Still present for later use if needed.

#### CompassViewModel:
Is a class within CompassView file, that is meant to update the currentHeading of the user to CompassView.

#### FetchModelView:
This file is used to display 3D models scanned by the LIDAR scanner.
Note: Is not currrently being used, will be used for a later iteration, to map out and locate edges of sidewalks to guide the user (still do not now if this can be done or if a change in approach would be needed)

#### Item.swift:
Stores timestamp data, was provided when the project was created to mark the file creation date.

#### Mesh+Ext:
Takes mesh data from ARKit (library). Essentially acquires the LIDAR data as a MDLMesh which we later process in ARWrapper, or could be used in FetchModelView to display the scanned surroundings

#### LocationManager:
Not relevant to object avoidance, ignore.

#### MiniMapView:
Not relevant to object avoidance, ignore.


