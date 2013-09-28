import processing.video.*;

import org.opencv.video.*;
import org.opencv.core.*;
import org.opencv.calib3d.*;
import org.opencv.contrib.*;
import org.opencv.objdetect.*;
import org.opencv.imgproc.*;
import org.opencv.utils.*;
import org.opencv.features2d.*;
import org.opencv.highgui.*;
import org.opencv.ml.*;
import org.opencv.photo.*;

import java.util.*;

import Blobscanner.*;

Detector detector;

boolean face_detect = false;

//Capture capture;
CascadeClassifier classifier;
ArrayList<Rect> faceRects;

ImageLibrary imageLibrary;

Mat resulted_x;
Mat resulted_y;

BackgroundSubtractorMOG background;

int w = 640*2;
int h = 480*2;

int videoW = w/2;
int videoH = h/2;

// to configure this as well to cut to small objects from detection
int MIN_OBJECT_AREA = 20*20;
int MAX_OBJECT_AREA = (int) Math.floor(videoH*videoW/1.5);

Slider history, mixtures, backgroundRatio, noiseSigma, erode;

Movie video;
PImage frame;

int frameCnt = 0;
int FRAME_RATE = 30;

Tuning tuning;

Map<String, List<Point>> trajectories = new HashMap();

void setup()
{
  System.loadLibrary(Core.NATIVE_LIBRARY_NAME);  
  classifier = new CascadeClassifier(dataPath("haarcascade_upperbody.xml"));
  faceRects = new ArrayList();
  
  imageLibrary = new ImageLibrary(this);

  /*
  Camera camera = new Camera(this);
  capture = camera.get();
  capture.start();
  */
    
  println(Core.NATIVE_LIBRARY_NAME);  
    
  tuning = new Tuning(); 
  
  flipMap(videoW, videoH);
  
  video = new Movie(this, "sample-cafe_x264.mov");
  video.loop();  
  
  size(w, h);
  frameRate(FRAME_RATE);
  
  history = new Slider("History", tuning.history, 3, 5, 150, videoH + 50, 300, 15, HORIZONTAL);
  mixtures = new Slider("Mixtures", tuning.mixtures, 0, 10, 150, videoH + 70, 300, 15, HORIZONTAL);
  backgroundRatio = new Slider("BG Ratio", tuning.backgroundRatio, 0, 1, 150, videoH + 90, 300, 15, HORIZONTAL);
  noiseSigma = new Slider("Noise Sigma", tuning.noiseSigma, 0, 1, 150, videoH + 110, 300, 15, HORIZONTAL);
  erode = new Slider("Erode/Dilate", tuning.erode, 1, 10, 150, videoH + 130, 300, 15, HORIZONTAL);
  
  background = new BackgroundSubtractorMOG((int) history.get(), (int) mixtures.get(), backgroundRatio.get(), noiseSigma.get());
  
  detector = new Detector(this, videoW, 0, videoW, videoH, 255);
  
  // called on shutdown
  prepareExitHandler();
}

void draw(){
  
  imageMode(CORNER);  
  
  if (video.available()) {
    video.read();
    frame = video;
  }
  
  image(frame, 0, 0);

  if (frame != null) 
  {
    
    Mat camMat = imageLibrary.toCV(frame);
    if(camMat == null){
      println("error");
    }
    
    /*
    Mat realCamFlipped = new Mat(videoW, videoH, CvType.CV_8UC4);
    Imgproc.remap(camMat, realCamFlipped, resulted_x, resulted_y, 0, 0, new Scalar(0, 0, 0));
    */
    
    Mat camFinal = new Mat(videoW, videoH, CvType.CV_8UC4);
    Imgproc.cvtColor(camMat, camFinal, Imgproc.COLOR_BGR2RGB, 0);
    
    Mat back = new Mat(videoW, videoH, CvType.CV_8UC1);
    background.apply(camFinal, back);
    
    // erosion/dillation element
    int erodeValue = (int) erode.get();
    Mat element = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, new Size(2*erodeValue+1, 2*erodeValue+1));
    
    // number of iterations - configurable - affects small details and people walking far from camera
    // TODO: implement detection based on size of image/relative distance from camera
    // erode
    Mat eroded = new Mat(videoW, videoH, CvType.CV_8UC1);
    Imgproc.erode(back, eroded, element); // back
    
    // dilate
    Mat dilated = new Mat(videoW, videoH, CvType.CV_8UC1);
    Imgproc.dilate(eroded, dilated, element);
    
    // 2nd phase
    // erode
    Mat eroded2 = new Mat(videoW, videoH, CvType.CV_8UC1);
    Imgproc.erode(dilated, eroded2, element); // back
    
    // dilate
    Mat dilated2 = new Mat(videoW, videoH, CvType.CV_8UC1);
    Imgproc.dilate(eroded2, dilated2, element);
    
    // apply gaussian blur
    Mat blured = new Mat(videoW, videoH, CvType.CV_8UC4);
    // significant blur - actually configurable
    int blur = 35; //15
    Imgproc.GaussianBlur(dilated2, blured, new Size(blur, blur), blur, blur);      
    
        
    // contours - need to copy to avoid image corruption by this method
    Mat forContours = blured.clone(); 
    List<MatOfPoint> contours = new ArrayList<MatOfPoint>();
    Imgproc.findContours(forContours, contours, new Mat(), Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE); // CHAIN_APPROX_SIMPLE?
    Imgproc.drawContours(camFinal, contours, -1, new Scalar(0, 0, 255), 3);
    
    
    // TODO: investigate motion abilities if have more time
    // Video.segmentMotion ...
    
    /*
    color contoursCol = color(255, 255, 0);
    int contoursThickness = 2;    
    PImage img = imageLibrary.toP5(blured);
    //img.filter(THRESHOLD);
    //img.loadPixels();    
    detector.imageFindBlobs(img);
    // to call always before to use a method returning or processing a blob feature
    detector.loadBlobsFeatures(); 
    detector.drawContours(contoursCol, contoursThickness);
    */
    
    // left - camera
    image(imageLibrary.toP5(camFinal), 0, 0, videoW, videoH);
    
    // right - greyscale
    image(imageLibrary.toP5(blured), width/2, 0, videoW, videoH); //dilated
    
    //println("Size = " + contours.size());
    
    // bottom sliders to play with some veriables
    stroke(204, 102, 0);
    strokeWeight(3);
    noFill();
    for (int i=0; i<contours.size(); i++)  {    
      Rect r = Imgproc.boundingRect(contours.get(i));    
      // area
      double area = r.width * r.height; 
      
      //println ("Area = " + area); 
      int x,y;
      
      boolean objectFound = false;
      
      // if the area is less than 20 px by 20px then it is probably just noise
      // if the area is the same as the 3/2 of the image size, probably just a bad filter
      if(area > MIN_OBJECT_AREA && area < MAX_OBJECT_AREA){
        objectFound = true;
      }
      else{
        objectFound = false;
      }  
      
      //println ("Object found = " + objectFound);
      
      // track only if we really found something valuable
      if(objectFound){        
        rect(r.x, r.y, r.width, r.height);
        // here we put logic which tracks actual object motion
        // we track upper left corner of bounding rect and draw its trajectory
        // also determine if this is human based on its speed and delta changing over time
      }
    }
    
    if(face_detect){
      Size minSize = new Size(150, 150);
      Size maxSize = new Size(450, 450);
      MatOfRect objects = new MatOfRect();
        
      Mat gray = new Mat(videoW, videoH, CvType.CV_8U);
      Imgproc.cvtColor(camMat, gray, Imgproc.COLOR_BGRA2GRAY);
      classifier.detectMultiScale(gray, objects, 1.1, 3, Objdetect.CASCADE_DO_CANNY_PRUNING | Objdetect.CASCADE_DO_ROUGH_SEARCH, minSize, maxSize);
      
      if(objects.toArray() != null && objects.toArray().length > 0){
        for( int j = 0; j < objects.toArray().length; j++ ){ 
          Rect current = objects.toArray()[j];
          imageMode(CORNER); 
          stroke(0);
          noFill();
          rect(current.x, current.y, current.width, current.height);
        }     
      }
    }
  }
  
  if (mousePressed) {
    history.mouseDragged();
    mixtures.mouseDragged();
    backgroundRatio.mouseDragged();
    noiseSigma.mouseDragged();
    erode.mouseDragged();
  }
  
  fill(25);
  rect(0, videoH, w, videoH);
  
  history.display();
  mixtures.display();
  backgroundRatio.display();
  noiseSigma.display();
  erode.display();
  
  
  fill(0, 102, 153);
  text((int)history.get(), 480, videoH + 60);
  text((int)mixtures.get(), 480, videoH + 80);
  text(backgroundRatio.get(), 480, videoH + 100);
  text(noiseSigma.get(), 480, videoH + 120);
  text(erode.get(), 480, videoH + 140);

}

// Called every time a new frame is available to read
void movieEvent(Movie m) {
  m.read();
  frame = m;
}

void mousePressed() {
  history.mousePressed();
  mixtures.mousePressed();
  backgroundRatio.mousePressed();
  noiseSigma.mousePressed();
  erode.mousePressed();
  
  resetBackground();
}

void mouseDragged(){
  history.mouseDragged();
  mixtures.mouseDragged();
  backgroundRatio.mouseDragged();
  noiseSigma.mouseDragged();
  erode.mouseDragged();
  
  resetBackground();
}

void keyPressed(){
  if(key == ' '){
    println("Refresh static background");
    resetBackground();
  }
}

private void prepareExitHandler () {  
  Runtime.getRuntime().addShutdownHook(new Thread(new Runnable() {  
    public void run () {      
      println("Saving all tuning parameters");
      // save all tuned values to file
      tuning.save((int) history.get(), (int) mixtures.get(), backgroundRatio.get(), noiseSigma.get(), (int) erode.get());   
    }  
  }));
}

void resetBackground(){
  background = new BackgroundSubtractorMOG((int) history.get(), (int) mixtures.get(), backgroundRatio.get(), noiseSigma.get());
}

void flipMap(int w, int h)
{   
   resulted_x = new Mat(h, w, CvType.CV_32FC1);
   resulted_y = new Mat(h, w, CvType.CV_32FC1);
   for( int j = 0; j < h; j++ ){ 
     for( int i = 0; i < w; i++ ){        
           resulted_x.put(j, i, w - i);
           resulted_y.put(j, i, j);  
       }
    }
}

