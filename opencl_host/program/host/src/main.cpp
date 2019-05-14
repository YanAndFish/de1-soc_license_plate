#include <iostream>
#include <stdlib.h>
#include "Parameter.h"
#include "base64.hpp"
#include <string>
#include <time.h>

#include "sys.hpp" //开启网络传输接口
sys sys;

#include "opt.h"   //带参运行
#include "video.h" //摄像头
#include "color.h" //opencl
#include <unistd.h>

#include <opencv2/opencv.hpp>
#include <pthread.h> //多线程
using namespace cv;
using namespace std;

extern unsigned char *host_input;	 //opencl数据输入指针
extern unsigned char *host_output;	//opencl数据输出指针
extern unsigned char *host_gray;	  //opencl灰度输出
extern unsigned char *surface_output; //软件处理YUYV输出指针
extern options opt;					  //带参运行
/*---------------------------------------------------------------------------------
带参运行说明：
-w 定义图像宽度
-h 定义图像高度
-l 定义循环次数
-image 使用一张较为理想的用摄像头拍摄的图片代替摄像头输入，但是摄像头仍会正常运行
<使用-image请设置分辨率960*720不然大概会死机>
-o 0:正常输出 1:输出RGB图 2:输出第一次HSV后的灰度图 3:输出第二次HSV后的灰度图 4:输出HSV、形态学后的灰度图
-nores 不进行模板比对
默认(-w960 -h720 -l100 -o0)

输出模式控制 : sys.output
	0: 正常输出  附带识别结果
	1: 输出RGB图
	2: 第一次对原图进行HSV变换
	3: 获得车牌遮罩
	4: 车牌图像
	5: 输出第二次HSV后的灰度图
	6: 输出HSV、形态学后的灰度图
---------------------------------------------------------------------------------*/
#if HW
Mat SDR3Image(opt.height, opt.width, CV_8UC3); //创建一个Mat，数据指向OpenCL的输出指针
Mat SDR1Image(opt.height, opt.width, CV_8UC1); //创建一个Mat，数据指向OpenCL的输出指针
Mat InputImage, GrayImage;
#else
Mat InputImage(opt.height, opt.width, CV_8UC3); //创建一个Mat，数据指向OpenCL的输出指针
Mat GrayImage(opt.height, opt.width, CV_8UC1);  //创建一个Mat，数据指向OpenCL的输出指针
#endif

/*定义图片查找字符*/
string Text[35] = {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"};
/*定义输入字模地址*/
string InputWordsFolderAddr = "../Word/";
string InputWordsSuffixName = ".bmp";

//多任务
Mat out;
pthread_t tids, copyRGBs;
struct thread_data //多任务进程传参结构体
{
	uchar *image_data;
	int image_w;
	int image_h;
	uchar *rgb_data;
	int rgb_w;
	int rgb_h;
	MaskRectic maskrectic;
	HSVRange Range;
} td, ha;
//================================================(子函数定义)
Mat RGB2HSVProcess(Mat InputArray);
Mat HSVProcess(Mat InputArray, HSVRange Range, MorphologyTimes *Times);
Mat MakeMask_HSV(Mat InputArray, HSVRange Range, MorphologyTimes *Times, MaskRectic *maskRectic);
void result(Mat InputArray, string *Word, MatchResult_One *result);
double Match(Mat InputArray, Mat InputTemplate);
Mat MakeMask_Word(Mat InputArray, MaskWord WordTarget);
void SetUp();
void _time(String pos);
void *hahahahaha(void *threadarg);
void *copyRGB(void *threadarg);
extern void buffer_dequeue(int index);
extern void buffer_dequeue(int index);
Mat DrawRectangle(Mat InputArray,Mat Mask,int line);
//================================================

/*
	程序主函数
*/
int main(int argc, char *argv[])
{
	_time("Start");

	sys.setup();//初始化网络连接
	cout << "\r\n";
	_time("set up TCP");

	options_init();				 //将参数设置为默认值
	parseArgs(argc, argv, &opt); //设置参数
#if HW
	SDR3Image.cols = opt.width;
	SDR3Image.rows = opt.height;
	SDR1Image.cols = opt.width;
	SDR1Image.rows = opt.height;
#else
	InputImage.cols = opt.width;
	InputImage.rows = opt.height;
	GrayImage.cols = opt.width;
	GrayImage.rows = opt.height;
#endif
	_time("set up option");

#if HW
	init_opencl();
	cout << "\r\n";
	_time("set up OpenCL");
#endif
	video_init();
	cout << "\r\n";
	_time("set up Cmaera");

	for (int i = 0; i < opt.loop; i++)
	{
		cout << "\r\n";
		cout << "new loop begin: " << i << "(" << opt.width << "x" << opt.height << ")" << endl;
		SetUp();
	}
	cout << "Host finish." << endl;
	pthread_join(tids, NULL);
	//sleep(2);	 //结束程序之前等待多线程也结束
	video_quit(); //摄像头用完关
	sys.close();  //断开tcp
#if HW
	cleanup(); //OpenCL清理缓存
#endif
	exit(EXIT_SUCCESS);
}

//=========================================================================

Mat RGB2HSVProcess(Mat InputArray)
{
	Mat OutputArray = Mat::zeros(InputArray.size(), InputArray.type());
	cvtColor(InputArray, OutputArray, COLOR_BGR2HSV);
	return OutputArray;
}

Mat HSVProcess(Mat InputArray, HSVRange Range, MorphologyTimes *Times)
{
	Mat Mask = Mat::zeros(InputArray.size(), InputArray.type());
	inRange(InputArray, Scalar(Range.HueMin, Range.SaturationMin, Range.ValueMin), Scalar(Range.HueMax, Range.SaturationMax, Range.ValueMax), Mask);
	Mat RowSe = getStructuringElement(MORPH_RECT, Size(1, 3));	//形态学操作对返回结构数组大小敏感
	erode(Mask, Mask, RowSe, Point(-1, -1), Times->ErodeTimes);   //形态学腐蚀(对白色区域而言)
	dilate(Mask, Mask, RowSe, Point(-1, -1), Times->DilateTimes); //形态学膨胀(对黑色区域而言)
	Mat ColSe = getStructuringElement(MORPH_RECT, Size(3, 1));	//形态学操作对返回结构数组大小敏感
	erode(Mask, Mask, ColSe, Point(-1, -1), Times->ErodeTimes);   //形态学腐蚀(对白色区域而言)
	dilate(Mask, Mask, ColSe, Point(-1, -1), Times->DilateTimes);
	return Mask;
}

Mat MakeMask_HSV(Mat Mask, HSVRange Range, MorphologyTimes *Times, MaskRectic *maskRectic)
{
#if DEBUG
	imshow("Mask", Mask);
	waitKey(0);
#endif // DEBUG

	Mat RowSe = getStructuringElement(MORPH_RECT, Size(1, 3));	//形态学操作对返回结构数组大小敏感
	erode(Mask, Mask, RowSe, Point(-1, -1), Times->ErodeTimes);   //形态学腐蚀(对白色区域而言)
	dilate(Mask, Mask, RowSe, Point(-1, -1), Times->DilateTimes); //形态学膨胀(对黑色区域而言)
	Mat ColSe = getStructuringElement(MORPH_RECT, Size(3, 1));	//形态学操作对返回结构数组大小敏感
	erode(Mask, Mask, ColSe, Point(-1, -1), Times->ErodeTimes);   //形态学腐蚀(对白色区域而言)
	dilate(Mask, Mask, ColSe, Point(-1, -1), Times->DilateTimes);

#if DEBUG
	imshow("Mask0", Mask);
	waitKey(0);
#endif // DEBUG

	//图片旋转矫正
	vector<vector<Point>> _contours;
	findContours(Mask, _contours, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);//外接矩形
	vector<Rect> _boundRect(_contours.size());
	if (_contours.size() != 0)
	{
		for (char i = 0; i < _contours.size(); i++)
		{
			_boundRect[i] = boundingRect(Mat(_contours[i]));
			float rate = _boundRect[i].width / _boundRect[i].height;
			if (rate < 1)
				rate = _boundRect[i].height / _boundRect[i].width;
			if ((rate >= 2) & (rate <= 4))
			{
				//需要获取的坐标
				CvPoint2D32f rectpoint[4];
				CvBox2D rect =minAreaRect(Mat(_contours[i]));

				cvBoxPoints(rect, rectpoint); //获取4个顶点坐标  
				//与水平线的角度  
				float angle = rect.angle;
				cout << angle << endl;

				int line1 = sqrt((rectpoint[1].y - rectpoint[0].y)*(rectpoint[1].y - rectpoint[0].y) + (rectpoint[1].x - rectpoint[0].x)*(rectpoint[1].x - rectpoint[0].x));
				int line2 = sqrt((rectpoint[3].y - rectpoint[0].y)*(rectpoint[3].y - rectpoint[0].y) + (rectpoint[3].x - rectpoint[0].x)*(rectpoint[3].x - rectpoint[0].x));

				//为了让正方形横着放，所以旋转角度是不一样的。竖放的，给他加90度，翻过来  
				if (line1 > line2) angle = 90 + angle;

				if (angle < 40){
					//进行旋转
					Point2f center = rect.center;  //中心点  
					Mat M2 = getRotationMatrix2D(center, angle, 1);//计算旋转加缩放的变换矩阵 
					warpAffine(Mask, Mask, M2, Mask.size(),1, 0, Scalar(0));//仿射变换 

					warpAffine(InputImage, InputImage, M2, InputImage.size(),1, 0, Scalar(0));//仿射变换 
				}
			}
		}
	}




	//遮罩提取
	float rate = 0.0;
	vector<vector<Point>> contours;
	findContours(Mask, contours, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);//外接矩形
	vector<Rect> boundRect(contours.size());

	if (contours.size() != 0)
	{
		for (char i = 0; i < contours.size(); i++)
		{

			boundRect[i] = boundingRect(Mat(contours[i]));
			rate = (float)boundRect[i].width / (float)boundRect[i].height;
			if (rate < 1)
				rate = (float)boundRect[i].height / (float)boundRect[i].width;
			if ((rate >= 2) & (rate <= 4))
			{
				Rect r = boundingRect(Mat(contours[i]));
				maskRectic->axis_x = r.x;
				maskRectic->axis_y = r.y;
				maskRectic->width = r.width;
				maskRectic->height = r.height;
				int Widthend = maskRectic->axis_x + maskRectic->width;
				int Heightend = maskRectic->axis_y + maskRectic->height;
				for (int width = maskRectic->axis_x; width < Widthend; width++)
				{
					for (int heighti = maskRectic->axis_y; heighti < Heightend; heighti++)
					{
						Mask.at<uchar>(heighti, width) = 255;
					}
				}
				cout << "rate0: " << rate << endl;
				//waitKey(0);
				out = Mat::zeros(Size(r.width, r.height), CV_8UC3);
InputImage.copyTo(out, Mask);

				return Mask;
			}
		}
	}
	return Mat::zeros(Size(1, 1), Mask.type());
}


Mat DrawRectangle(Mat InputArray,Mat Mask,int line)//画框(输入图像，蒙板，线粗)
{
	Mat BigMask, Border,Color;
	dilate(Mask,BigMask, getStructuringElement(MORPH_RECT, Size(line,line)) , Point(-1, -1), 1);
	Border = BigMask - Mask;
	Mat _temp(Mask.rows, Mask.cols, CV_8UC3, Scalar(0, 0, 255));
	_temp.copyTo(Color, Border);
	//imshow("_temp", Color);
	InputArray += Color;
	return InputArray;
}

void _time(String pos) //测量时间
{
	struct timespec ts;
	static double old_time;
	clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
	double st = ts.tv_sec * 1000.0 + ts.tv_nsec / 1000000.0;
	cout << "T:<" << pos << ">-->" << (st - old_time) << " ms." << endl;
	old_time = st;
}

void SetUp()
{
#if HW
	buffer_dequeue(0);
	_time("video buffer on");
	yuyv2rgb_hw(host_input, sys.phn, sys.phx, sys.psn, sys.psx, sys.pvn, sys.pvx); //hmin,hmax,smin,smax,vmin,vmax
	_time("run OpenCL");
	buffer_enqueue(0);
	_time("video buffer off");
	//_time("get image for OpenCL");
	if (opt.image != 0)
	{
		GrayImage = imread("../Word/cam_gray.jpg", 0);
	}
	else
	{
		SDR1Image.data = host_gray;
		SDR1Image.copyTo(GrayImage);
	}
	_time("copy image (SDRAM->DDR3)(HSV)");
	if (opt.image != 0)
		InputImage = imread("../Word/cam_rgb.jpg", 1);
	else {
		/*
		pthread_join(copyRGBs, NULL);
		pthread_create(&copyRGBs, NULL, copyRGB, (void *)(&ha));
		*/
		SDR3Image.data = host_output;
		SDR3Image.copyTo(InputImage);
	}
		//_time("copy image (SDRAM->DDR3)(RGB)");
#else
	buffer_dequeue(0);
	_time("video buffer on");
	video_get_surface();
	_time("get image for CPU(YUYV->RGB)");
	buffer_enqueue(0);
	_time("video buffer off");
	InputImage.data = surface_output;
#endif
	//可修改标记 查找车牌
	HSVRange Range = {sys.phn, sys.phx, sys.psn, sys.psx, sys.pvn, sys.pvx}; //0,180,0,255,0,255
	MaskRectic maskrectic = {0, 0, 0, 0};
	MorphologyTimes morphologytimes = {3, 15};
#if HW
	if (sys.output == 2)
	{
		sys.send(GrayImage, "\"result\":\"\"");
		return;
	}


	if (sys.output == 1)
	{
		sys.send(InputImage, "\"result\":\"\"");
		return;
	}

	Mat Mask = MakeMask_HSV(GrayImage, Range, &morphologytimes, &maskrectic);
	_time("MakeMask_HSV");
	//Mat Maskword = HSVProcess(RGB2HSVProcess(InputImage), Range, &morphologytimes);

	if (Mask.rows == 1) //这应该就是没图
	{
		sys.send(InputImage, "\"result\":\"\\u627e\\u4e0d\\u5230\\u8f66\\u724c\""); //找不到车牌
		_time("No license plate found");
		return;
	}
#else
	cvtColor(InputImage, InputImage, COLOR_BGR2HSV);
	_time("RGB->HSV");
	inRange(InputImage, Scalar(Range.HueMin, Range.SaturationMin, Range.ValueMin), Scalar(Range.HueMax, Range.SaturationMax, Range.ValueMax), GrayImage);
	Mat Mask = MakeMask_HSV(GrayImage, Range, &morphologytimes, &maskrectic);
	if (Mask.rows == 1) //这应该就是没图
	{
		sys.send(InputImage, "\"result\":\"\\u627e\\u4e0d\\u5230\\u8f66\\u724c\""); //找不到车牌
		_time("No license plate found");
		return;
	}
#endif
	_time("HSV->Mask");
	

	if (sys.output == 3)
	{
		// 获得车牌遮罩
		sys.send(Mask, "\"result\":\"\"");
		return;
	}

	//_time("make some void Mat");
	//Mat GetSe = getStructuringElement(MORPH_RECT, Size(3, 3)); //形态学操作对返回结构数组大小敏感
	//morphologyEx(Maskword, Maskword, MORPH_CLOSE, GetSe);      //形态学操作函数 此处使用开操作（先腐蚀后膨胀）


	if (sys.output == 4)
	{ // 车牌图像
		sys.send(out, "\"result\":\"\"");
		return;
	}
	//rectangle(InputImage, cvPoint(maskrectic.axis_x, maskrectic.axis_y), cvPoint(maskrectic.axis_x + maskrectic.width, maskrectic.axis_y + maskrectic.height), Scalar(0, 0, 255), 3, 4);

	Mat image_frame=DrawRectangle(InputImage,Mask,10);
	_time("DrawRectangle");



	pthread_join(tids, NULL);

	td.image_h = out.rows;//车牌图
	td.image_w = out.cols;
	td.image_data = out.data;

	td.rgb_h = image_frame.rows;//原图
	td.rgb_w = image_frame.cols;
	td.rgb_data = image_frame.data;
 
	td.Range = Range;
	td.maskrectic = maskrectic;//车牌遮罩

	//参数依次是：创建的线程id，线程参数，调用的函数，传入的函数参数
	pthread_create(&tids, NULL, hahahahaha, (void *)(&td));

	_time("RGB + Mask to out");
}

bool make_check (MaskWord _mase){
	if ( abs(_mase.vertex_x) > 570
		|| abs(_mase.vertex_y) > 190
		|| abs(_mase.vertex_x + _mase.width)  > 570
		|| abs(_mase.vertex_y + _mase.height) > 190
		|| _mase.width <= 0
		|| _mase.height <= 0
		)
		return false;
	else
		return true;
}


//新的线程
void *hahahahaha(void *threadarg)
{
	//pthread_t myid = pthread_self();
	thread_data *my_data = (thread_data *)threadarg;

	_time("pthread run----------");

	//转换参数
	int w = my_data->image_w;
	int h = my_data->image_h;
	Mat out(h, w, CV_8UC3, (uchar *)my_data->image_data);
	Mat rgb(my_data->rgb_h, my_data->rgb_w, CV_8UC3, (uchar *)my_data->rgb_data);
	MaskRectic maskrectic = my_data->maskrectic;
	HSVRange Range = my_data->Range;


	Mat Targetwords = Mat::zeros(Size(maskrectic.width, maskrectic.height), CV_8UC3);
	Mat TargetGray = Mat::zeros(Size(maskrectic.width, maskrectic.height), CV_8UC3);
	Mat Target0 = Mat::zeros(Size(maskrectic.width, maskrectic.height), CV_8UC3);
	/*创建车牌预备空间*/
	Mat Word0 = Mat::zeros(Size(1, 1), CV_8UC3);
	Mat Word1 = Mat::zeros(Size(1, 1), CV_8UC3);
	Mat Word2 = Mat::zeros(Size(1, 1), CV_8UC3);
	Mat Word3 = Mat::zeros(Size(1, 1), CV_8UC3);
	Mat Word4 = Mat::zeros(Size(1, 1), CV_8UC3);
	Mat Word5 = Mat::zeros(Size(1, 1), CV_8UC3);
	Mat Word6 = Mat::zeros(Size(1, 1), CV_8UC3);

	
	Mat Target = out(Rect(maskrectic.axis_x, maskrectic.axis_y, maskrectic.width, maskrectic.height));

	//_time("RGB + mask->out");

	Mat GetSe = getStructuringElement(MORPH_RECT, Size(3, 3)); //形态学操作对返回结构数组大小敏感
	//morphologyEx(Maskword, Maskword, MORPH_CLOSE, GetSe);					//形态学操作函数 此处使用开操作（先腐蚀后膨胀）

	//Target = out(Rect(maskrectic.axis_x, maskrectic.axis_y, maskrectic.width, maskrectic.height));

	//尺寸调整

	cout << "before w" << Target.cols << "h" << Target.rows << endl;
	resize(Target,Target,Size(570,190),0,0,INTER_LINEAR);
	cout << "now w" << Target.cols << "h" << Target.rows << endl;
	Target.copyTo(Target0);

	//色相，饱和度，明度
	//可修改标记 第二次 查找白色的文字
	Range = {sys.thn, sys.thx, sys.tsn, sys.tsx, sys.tvn, sys.tvx}; //{ 0, 180, 0, 70, 180, 255 }
	//上面那一堆参数用于识别摄像头的定帧已经验证可行

	//Range = {0, 180, 0, 130, 140, 255}; //{ 0, 180, 0, 70, 180, 255 }

	cvtColor(Target, Target, COLOR_BGR2HSV);
	inRange(Target, Scalar(Range.HueMin, Range.SaturationMin, Range.ValueMin), Scalar(Range.HueMax, Range.SaturationMax, Range.ValueMax), Target);
	Target.copyTo(TargetGray);

	//发送车牌图像
	if (sys.output == 5)
	{
		sys.send(Target, "\"result\":\"\"");
		cout << "pthread finish!" << endl;
		pthread_exit(NULL);
	}
	Mat RowSe = getStructuringElement(MORPH_RECT, Size(1, 3)); //形态学操作对返回结构数组大小敏感
	dilate(Target, Target, RowSe, Point(-1, -1), 1);
	erode(Target, Target, RowSe, Point(-1, -1), 1);			   //形态学腐蚀(对白色区域而言)
	dilate(Target, Target, RowSe, Point(-1, -1), 4);		   //形态学膨胀(对黑色区域而言)
	Mat ColSe = getStructuringElement(MORPH_RECT, Size(3, 1)); //形态学操作对返回结构数组大小敏感
	dilate(Target, Target, ColSe, Point(-1, -1), 1);
	erode(Target, Target, ColSe, Point(-1, -1), 1);  //形态学腐蚀(对白色区域而言)
	dilate(Target, Target, ColSe, Point(-1, -1), 4); //形态学膨胀(对黑色区域而言)

	erode(Target, Target, getStructuringElement(MORPH_RECT, Size(5, 5)), Point(-1, -1), 3);
	erode(Target, Target, getStructuringElement(MORPH_RECT, Size(1, 3)), Point(-1, -1), 1);
	//(Target, Target, getStructuringElement(MORPH_RECT, Size(1, 3)), Point(-1, -1), 1);
	dilate(Target, Target, getStructuringElement(MORPH_RECT, Size(3, 3)), Point(-1, -1), 4);
	//上面那一堆参数用于识别摄像头的定帧已经验证可行

	//erode(Target, Target, getStructuringElement(MORPH_RECT, Size(5, 5)), Point(-1, -1), 4);
	//erode(Target, Target, getStructuringElement(MORPH_RECT, Size(1, 3)), Point(-1, -1), 1);
	//(Target, Target, getStructuringElement(MORPH_RECT, Size(1, 3)), Point(-1, -1), 1);
	//dilate(Target, Target, getStructuringElement(MORPH_RECT, Size(2, 2)), Point(-1, -1), 8);

	//发送车牌形态学
	if (sys.output == 6)
	{
		sys.send(Target, "\"result\":\"\"");
		cout << "pthread finish!" << endl;
		pthread_exit(NULL);
	}

	if (opt.nores == 0)
	{

		int BoxLong_x[14];
		int BoxNum[14];
		int useablenum = 0;
		vector<vector<Point>> contours;
		vector<Vec4i> hierarcy;
		findContours(Target, contours, hierarcy, RETR_EXTERNAL, CHAIN_APPROX_NONE);
		vector<Rect> boundRect(contours.size());  //定义外接矩形集合
		vector<RotatedRect> box(contours.size()); //定义最小外接矩形集合
		Point2f rect[4];
		if (contours.size() >= 7 /* && contours.size() < 10*/)
		{

			/* 车牌文字最小外接矩形循环 开始 */
			for (int i = 0; i < contours.size(); i++)
			{
				char sum = 0;
				box[i] = minAreaRect(Mat(contours[i])); //计算每个轮廓最小外接矩形

				float rate = box[i].size.width / box[i].size.height; //长宽比
				if (rate > 1) rate = box[i].size.height / box[i].size.width;

#if DEBUG
				cout << box[i].angle << endl;
				cout << box[i].center << endl;
				cout << "size.width:" << box[i].size.width << endl;
				cout << "size.height:" << box[i].size.height << endl;
				cout << "rate:" << rate << endl;
#endif // DEBUG

				if ((rate < 0.62) & ((box[i].size.height / Target.rows > 0.2) | (box[i].size.width / Target.rows > 0.2)))
				{

					boundRect[i] = boundingRect(Mat(contours[i]));
					BoxLong_x[i] = box[i].center.x;
					BoxNum[i] = i;
#if DEBUG
					cout << "BoxLong_x:" << i << "  " << BoxLong_x[i] << endl;
					cout << "BoxNum:" << i << "  " << BoxNum[i] << endl;
#endif // DEBUG

					useablenum ++;
				} else {
					BoxNum[i] = 14 - sum;
					BoxLong_x[i] = 5000;
					sum ++;
				}
				cout << endl;
			}
			/* 车牌文字最小外接矩形循环 结束 */

			for (int i = 0; i < contours.size() - 1; i++) //冒泡法排序
			{
				for (int j = 0; j < contours.size() - 2; j++)
				{
					if (BoxLong_x[j] > BoxLong_x[j + 1])
					{
						int Temp0 = BoxLong_x[j];
						BoxLong_x[j] = BoxLong_x[j + 1];
						BoxLong_x[j + 1] = Temp0;
						int Temp1 = BoxNum[j];
						BoxNum[j] = BoxNum[j + 1];
						BoxNum[j + 1] = Temp1;
					}
				}
			}
#if DEBUG
			cout << "pthread 冒泡法" << endl;

			for (int i = 0; i < useablenum + 2; i++)
			{
				//putText(Target0, NumTest[BoxNum[i]], Point(box[BoxNum[i]].center.x, box[BoxNum[i]].center.y),FONT_HERSHEY_COMPLEX,1,Scalar(0,0,0),2);
				cout << "BoxNumout:" << i << "  " << BoxNum[i] << "  X locate:" << BoxLong_x[i] << endl;
			}
#endif
			if (useablenum + 2 >= 6)
			{
				cout << "538" << endl;
				MaskWord TargectWordMask0 = {boundRect[BoxNum[0]].x, boundRect[BoxNum[0]].y, boundRect[BoxNum[0]].width, boundRect[BoxNum[0]].height};
//cout << "0 " << boundRect[BoxNum[0]].x << " " << boundRect[BoxNum[0]].y << " " << boundRect[BoxNum[0]].width << " " << boundRect[BoxNum[0]].height << " " << endl;
				if (!make_check(TargectWordMask0)) {
					sys.send(rgb, "\"result\":\"\"");
					cout << "pthread finish!" << endl;
					pthread_exit(NULL);
				}

				MaskWord TargectWordMask1 = {boundRect[BoxNum[1]].x, boundRect[BoxNum[1]].y, boundRect[BoxNum[1]].width, boundRect[BoxNum[1]].height};
//cout << "1 " << boundRect[BoxNum[1]].x << " " << boundRect[BoxNum[1]].y << " " << boundRect[BoxNum[1]].width << " " << boundRect[BoxNum[1]].height << " " << endl;
				if (!make_check(TargectWordMask1)) {
					sys.send(rgb, "\"result\":\"\"");
					cout << "pthread finish!" << endl;
					pthread_exit(NULL);
				}


				MaskWord TargectWordMask2 = {boundRect[BoxNum[2]].x, boundRect[BoxNum[2]].y, boundRect[BoxNum[2]].width, boundRect[BoxNum[2]].height};
//cout << "2 " << boundRect[BoxNum[2]].x << " " << boundRect[BoxNum[2]].y << " " << boundRect[BoxNum[2]].width << " " << boundRect[BoxNum[2]].height << " " << endl;
				if (!make_check(TargectWordMask2)) {
					sys.send(rgb, "\"result\":\"\"");
					cout << "pthread finish!" << endl;
					pthread_exit(NULL);
				}


				MaskWord TargectWordMask3 = {boundRect[BoxNum[3]].x, boundRect[BoxNum[3]].y, boundRect[BoxNum[3]].width, boundRect[BoxNum[3]].height};
//cout << "3 " << boundRect[BoxNum[3]].x << " " << boundRect[BoxNum[3]].y << " " << boundRect[BoxNum[3]].width << " " << boundRect[BoxNum[3]].height << " " << endl;
				if (!make_check(TargectWordMask3)) {
					sys.send(rgb, "\"result\":\"\"");
					cout << "pthread finish!" << endl;
					pthread_exit(NULL);
				}


				MaskWord TargectWordMask4 = {boundRect[BoxNum[4]].x, boundRect[BoxNum[4]].y, boundRect[BoxNum[4]].width, boundRect[BoxNum[4]].height};
//cout << "4 " << boundRect[BoxNum[4]].x << " " << boundRect[BoxNum[4]].y << " " << boundRect[BoxNum[4]].width << " " << boundRect[BoxNum[4]].height << " " << endl;
				if (!make_check(TargectWordMask4)) {
					sys.send(rgb, "\"result\":\"\"");
					cout << "pthread finish!" << endl;
					pthread_exit(NULL);
				}


				MaskWord TargectWordMask5 = {boundRect[BoxNum[5]].x, boundRect[BoxNum[5]].y, boundRect[BoxNum[5]].width, boundRect[BoxNum[5]].height};
//cout << "5 " << boundRect[BoxNum[5]].x << " " << boundRect[BoxNum[5]].y << " " << boundRect[BoxNum[5]].width << " " << boundRect[BoxNum[5]].height << " " << endl;
				if (!make_check(TargectWordMask5)) {
					sys.send(rgb, "\"result\":\"\"");
					cout << "pthread finish!" << endl;
					pthread_exit(NULL);
				}


				MaskWord TargectWordMask6 = {boundRect[BoxNum[6]].x, boundRect[BoxNum[6]].y, boundRect[BoxNum[6]].width, boundRect[BoxNum[6]].height};
//cout << "6 " << boundRect[BoxNum[6]].x << " " << boundRect[BoxNum[6]].y << " " << boundRect[BoxNum[6]].width << " " << boundRect[BoxNum[6]].height << " " << endl;
				if (!make_check(TargectWordMask6)) {
					sys.send(rgb, "\"result\":\"\"");
					cout << "pthread finish!" << endl;
					pthread_exit(NULL);
				}


cout << "553" << endl;
				Mat TargectWord0 = MakeMask_Word(Target, TargectWordMask0);
				Mat TargectWord1 = MakeMask_Word(Target, TargectWordMask1);
				Mat TargectWord2 = MakeMask_Word(Target, TargectWordMask2);
				Mat TargectWord3 = MakeMask_Word(Target, TargectWordMask3);
				Mat TargectWord4 = MakeMask_Word(Target, TargectWordMask4);
				Mat TargectWord5 = MakeMask_Word(Target, TargectWordMask5);
				Mat TargectWord6 = MakeMask_Word(Target, TargectWordMask6);
cout << "524" << endl;
				TargetGray.copyTo(Word0);
				Word0 = Word0(Rect(TargectWordMask0.vertex_x, TargectWordMask0.vertex_y, TargectWordMask0.width, TargectWordMask0.height));
				resize(Word0, Word0, Size(32, 50),0,0,INTER_LINEAR);
				TargetGray.copyTo(Word1);
				Word1 = Word1(Rect(TargectWordMask1.vertex_x, TargectWordMask1.vertex_y, TargectWordMask1.width, TargectWordMask1.height));
				resize(Word1, Word1, Size(32, 50),0,0,INTER_LINEAR);
				TargetGray.copyTo(Word2);
				Word2 = Word2(Rect(TargectWordMask2.vertex_x, TargectWordMask2.vertex_y, TargectWordMask2.width, TargectWordMask2.height));
				resize(Word2, Word2, Size(32, 50),0,0,INTER_LINEAR);
				TargetGray.copyTo(Word3);
				Word3 = Word3(Rect(TargectWordMask3.vertex_x, TargectWordMask3.vertex_y, TargectWordMask3.width, TargectWordMask3.height));
				resize(Word3, Word3, Size(32, 50),0,0,INTER_LINEAR);
				TargetGray.copyTo(Word4);
				Word4 = Word4(Rect(TargectWordMask4.vertex_x, TargectWordMask4.vertex_y, TargectWordMask4.width, TargectWordMask4.height));
				resize(Word4, Word4, Size(32, 50),0,0,INTER_LINEAR);
				TargetGray.copyTo(Word5);
				Word5 = Word5(Rect(TargectWordMask5.vertex_x, TargectWordMask5.vertex_y, TargectWordMask5.width, TargectWordMask5.height));
				resize(Word5, Word5, Size(32, 50),0,0,INTER_LINEAR);
				TargetGray.copyTo(Word6);
				Word6 = Word6(Rect(TargectWordMask6.vertex_x, TargectWordMask6.vertex_y, TargectWordMask6.width, TargectWordMask6.height));
				resize(Word6, Word6, Size(32, 50),0,0,INTER_LINEAR);
cout << "646" << endl;
				MatchResult_One ResultWord1;
				result(Word1, Text, &ResultWord1);
				MatchResult_One ResultWord2;
				result(Word2, Text, &ResultWord2);
				MatchResult_One ResultWord3;
				result(Word3, Text, &ResultWord3);
				MatchResult_One ResultWord4;
				result(Word4, Text, &ResultWord4);
				MatchResult_One ResultWord5;
				result(Word5, Text, &ResultWord5);
				MatchResult_One ResultWord6;
				result(Word6, Text, &ResultWord6);
cout << "603" << endl;
/*
				cout << "MAX1:" << Text[ResultWord1.ResultNumber]
					 << "  resultMax" << ResultWord1.ResultMax << endl;
				cout << "MAX2:" << Text[ResultWord2.ResultNumber]
					 << "  resultMax" << ResultWord2.ResultMax << endl;
				cout << "MAX3:" << Text[ResultWord3.ResultNumber]
					 << "  resultMax" << ResultWord3.ResultMax << endl;
				cout << "MAX4:" << Text[ResultWord4.ResultNumber]
					 << "  resultMax" << ResultWord4.ResultMax << endl;
				cout << "MAX5:" << Text[ResultWord5.ResultNumber]
					 << "  resultMax" << ResultWord5.ResultMax << endl;
				cout << "MAX6:" << Text[ResultWord6.ResultNumber]
					 << "  resultMax" << ResultWord6.ResultMax << endl;
*/
				string _result = Text[ResultWord1.ResultNumber] + Text[ResultWord2.ResultNumber] + Text[ResultWord3.ResultNumber] + Text[ResultWord4.ResultNumber] + Text[ResultWord5.ResultNumber] + Text[ResultWord6.ResultNumber];
				cout << "result: " << _result << endl;
				if (sys.output == 0)
					sys.send(rgb, "\"result\":\"" + _result + "\"");
				cout << "pthread return" << endl;
				pthread_exit(NULL);
			}
		}
	}
	//https://github.com/RonnyldoSilva/Opencv-Mat-to-Base64//
	if (sys.output == 0)
		sys.send(rgb, "\"result\":\"\"");

	cout << "pthread finish! no result!" << endl;
	pthread_exit(NULL);
}

Mat MakeMask_Word(Mat InputArray, MaskWord WordTarget)
{
	Mat Mask = Mat::zeros(InputArray.size(), InputArray.type());

	int Widthend = WordTarget.vertex_x + WordTarget.width;
	int Heightend = WordTarget.vertex_y + WordTarget.height;

	for (int width = WordTarget.vertex_x; width < Widthend; width++)
	{
		for (int heighti = WordTarget.vertex_y; heighti < Heightend; heighti++)
		{
			Mask.at<uchar>(heighti, width) = 255;
		}
	}
	return Mask;
}

double Match(Mat InputArray, Mat InputTemplate)
{

	cvtColor(InputTemplate, InputTemplate, COLOR_BGR2GRAY);

	int width = 1;
	int height = 1;

	Mat matchumg(width, height, CV_32F); //CV_16F

	matchTemplate(InputArray, InputTemplate, matchumg, TM_CCORR_NORMED); //它滑动过整个图像 image, 用指定方法比较 temp 与图像尺寸为 w×h 的重叠区域，并且将比较结果存到 matchumg 中。
	double maxValue = matchumg.at<float>(0, 0);

#if DEBUG
	cout << "InputArray row: " << InputArray.rows << endl;
	cout << "InputArray col: " << InputArray.cols << endl;
	cout << "InputTemplate row: " << InputTemplate.rows << endl;
	cout << "InputTemplate col: " << InputTemplate.cols << endl;
	cout << "matchumg row: " << matchumg.rows << endl;
	cout << "matchumg col: " << matchumg.cols << endl;
	cout << "maxValue: " << maxValue << endl;
#endif // DEBUG

	return maxValue;
}
void result(Mat InputArray, string *Word, MatchResult_One *result)
{
	char resultNum = 0;
	double resultMax = 0;
	const char TempMax = 34;
	double Temp[34];
	for (char i = 0; i < TempMax; i++)
	{
		string InputWordsName = Word[i];
		string InputWordsNameInfo = InputWordsFolderAddr + InputWordsName + InputWordsSuffixName;
		Mat Words = imread(InputWordsNameInfo);
		Temp[i] = Match(InputArray, Words);
	}
	for (char i = 0; i < TempMax; i++)
	{
		if (Temp[i] > resultMax)
		{
			resultMax = Temp[i];
			resultNum = i;
		}
	}
	result->ResultMax = resultMax;
	result->ResultNumber = resultNum;

#if DEBUG

	for (char i = 0; i < TempMax; i++)
	{
		cout << Word[i] << "=" << Temp[i] << endl;
	}
	cout << "MAX:" << Word[result->ResultNumber] << endl
		 << "resultMax" << result->ResultMax << endl;

	waitKey(0);
#endif // DEBUG
}

#if HW
void *copyRGB(void *threadarg)
{
	SDR3Image.data = host_output;
	SDR3Image.copyTo(InputImage);
	//cout << "copy RGB done." << endl;
	pthread_exit(NULL);
}
#endif