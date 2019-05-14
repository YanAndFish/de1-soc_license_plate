#ifndef sys_hpp
#define sys_hpp

#include <iostream>
#include <stdio.h>
#include <string>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <opencv2/opencv.hpp> //为了支持mat
#include "base64.hpp"


//http://rapidjson.org/zh-cn/ 

#include <fstream>//文件流
#include "document.h"
#include "writer.h"
#include "stringbuffer.h"

#include <pthread.h> //多线程

class sys {
  public:
    int  setup();
    void send(cv::Mat data ,std::string json);
    void close();
    static void * recv_loop_pth(void* __this);

    /* 设置 */
    int output = 0; // 输出模式

    //查找车牌的参数 缩写成这样是因为要减少json传输量
    int phn =  80; //HueMin
    int phx =  120;//HueMax
    int psn =  150;//SaturationMin
    int psx =  255;//SaturationMax
    int pvn =  0;  //ValueMin
    int pvx =  255;//ValueMax

    //查找文字的参数
    int thn =  0;  //HueMin
    int thx =  180;//HueMax
    int tsn =  0;  //SaturationMin
    int tsx =  90; //SaturationMax
    int tvn =  210;//ValueMin
    int tvx =  255;//ValueMax

  private:
    int client_sockfd = -1; // tcp连接符

};


#endif /* sys_hpp */

