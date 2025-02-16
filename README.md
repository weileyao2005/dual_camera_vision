# dual_camera_vision
it's the project i did in the GEARS program held by NCSU.  
in a word this code use two cameras to detect the depth of the object
and of course you get to choose the object.  
when first thinking about how to tackle it, there are few matlab code on git, so i decided to upload mine when mine's finished.

//The annotation in the code is in chinese   

as you can see the code is in matlab. in the future i might transit it into python using lib in open CV  
the name is pretty straight forward, it kinda explains itself..  

--------------------------------------------------------------  

the whole prcess is: cpature stereo pictures -> save strero params -> test the params (if needed) -> main.m  

so i didn't find a better way to capture stereo pictures, the 'captureStereopictures.m' can capture pictures from two 
cameras at a time gap of 0.04s, which provide better accuracy even when i hold the checcerboard in one hand and click the 
gui button in the other.  

--------------------------------------------------------------  

next is to use the strerocameras app in the matlab, and follow the steps, remember to tic '3 parameter' when calibrating it.  
and save the result, then run the savestreroparams.m or just paste it and press enter.  

--------------------------------------------------------------  

finally, run the main.m  
it provide a preety good accuracy. when encounter failure it might because the lack of feature points, you can alter the index.  

--------------------------------------------------------------
