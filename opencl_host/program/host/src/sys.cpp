#include "sys.hpp"

#include <iostream>
#include <stdio.h>
#include <string>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sstream>
#include <opencv2/opencv.hpp> //为了支持mat
#include "base64.hpp"


//http://rapidjson.org/zh-cn/ 

#include <fstream>//文件流
#include "document.h"
#include "writer.h"
#include "stringbuffer.h"

#include <pthread.h> //多线程

using namespace rapidjson;
using namespace std;
//初始化
int sys::setup(){

  //默认设置
  string _ip = "192.168.15.5";//conf["ip"].GetString();
  int _port = 9998;

  //读取配置文件
  fstream t;
  int length;
  t.open("./setting.json");      // open input file
  t.seekg(0, std::ios::end);    // go to the end
  length = t.tellg();           // report location (this is the length)
  t.seekg(0, std::ios::beg);    // go back to the beginning
  char *buffer = new char[length];    // allocate memory for a buffer of appropriate dimension
  t.read(buffer, length);       // read the whole file into the buffer
  t.close();                    // close file handle

  Document conf;
  conf.Parse(buffer);
  if (conf.IsObject()){
    if (conf.HasMember("ip") && conf["ip"].IsString())  _ip = conf["ip"].GetString();//设置IP
    if (conf.HasMember("port") && conf["port"].IsInt()) _port = conf["port"].GetInt();//设置端口
    printf("load setting.json:\r\n%s\r\n",buffer);
  }

  //初始化连接信息
  struct sockaddr_in remote_addr; //服务器端网络地址结构体
  memset(&remote_addr,0,sizeof(remote_addr)); //数据初始化--清零
  remote_addr.sin_family=AF_INET; //设置为IP通信
  remote_addr.sin_addr.s_addr=inet_addr((char*)_ip.data());//服务器IP地址
  remote_addr.sin_port=htons(_port); //服务器端口号

  // 创建客户端套接字--IPv4协议，面向连接通信，TCP协议
  if((client_sockfd = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP))<0)
  {
    client_sockfd = 0;
    perror("socket error");
    return 0;
  }

  //将套接字绑定到服务器的网络地址上
  if(connect(client_sockfd,(struct sockaddr *)&remote_addr,sizeof(struct sockaddr))<0)
  {
    client_sockfd = 0;
    perror("connect error");
    return 0;
  }
  printf("connected to server\r\n");

  int sbuflen = 212992;
  setsockopt(client_sockfd, IPPROTO_TCP, SO_SNDBUF, (const char*)&sbuflen, sizeof(int));

  //创建多线程
  pthread_t pth;
  pthread_create(&pth,NULL,recv_loop_pth,(void*)this);
  return 0;


  /*::close(client_sockfd);*/
  //client_sockfd = 0;

}


//一个新的线程，专门用来接收消息
void * sys::recv_loop_pth(void* __this){
  sys * _this =(sys *)__this;//_this->
  int len;
  char buf[BUFSIZ];  //数据传送的缓冲区
  printf("new pth\r\n");
  while(1)
  {
    len = ::recv(_this->client_sockfd,buf,BUFSIZ,0);
    printf("received:%s\r\n",buf);
    Document conf;
    conf.Parse(buf);
    if (conf.IsObject()){
      if (conf.HasMember("o") && conf["o"].IsInt()) _this->output = conf["o"].GetInt();//输出模式

      if (conf.HasMember("phn") && conf["phn"].IsInt()) _this->phn = conf["phn"].GetInt();//HueMin
      if (conf.HasMember("phx") && conf["phx"].IsInt()) _this->phx = conf["phx"].GetInt();//HueMax
      if (conf.HasMember("psn") && conf["psn"].IsInt()) _this->psn = conf["psn"].GetInt();//SaturationMin
      if (conf.HasMember("psx") && conf["psx"].IsInt()) _this->psx = conf["psx"].GetInt();//SaturationMax
      if (conf.HasMember("pvn") && conf["pvn"].IsInt()) _this->pvn = conf["pvn"].GetInt();//ValueMin
      if (conf.HasMember("pvx") && conf["pvx"].IsInt()) _this->pvx = conf["pvx"].GetInt();//ValueMax

      if (conf.HasMember("thn") && conf["thn"].IsInt()) _this->thn = conf["thn"].GetInt();//HueMin
      if (conf.HasMember("thx") && conf["thx"].IsInt()) _this->thx = conf["thx"].GetInt();//HueMax
      if (conf.HasMember("tsn") && conf["tsn"].IsInt()) _this->tsn = conf["tsn"].GetInt();//SaturationMin
      if (conf.HasMember("tsx") && conf["tsx"].IsInt()) _this->tsx = conf["tsx"].GetInt();//SaturationMax
      if (conf.HasMember("tvn") && conf["tvn"].IsInt()) _this->tvn = conf["tvn"].GetInt();//ValueMin
      if (conf.HasMember("tvx") && conf["tvx"].IsInt()) _this->tvx = conf["tvx"].GetInt();//ValueMax
    }
    memset(buf, 0, sizeof(buf));
  }
}



//发送数据包
void sys::send(cv::Mat data ,std::string json){
  if (client_sockfd < 0) return;
  // 一个数据包结构：
  // int json_len | int image_len | json image
  // json 示例 尾部不加逗号  "result":"辽C 12345"

  //转换图片
  std::vector<uchar> buf;
  cv::imencode(".jpg", data, buf);
  uchar *result = reinterpret_cast<uchar *>(&buf[0]);
  std::string base64_img = "data:image/jpg;base64," + base64_encode(result, buf.size());

  //json加料
  json = "{\"o\": " + to_string(this->output)
    + ",\"phn\": " + to_string(this-> phn)
    + ",\"phx\": " + to_string(this-> phx)
    + ",\"psn\": " + to_string(this-> psn)
    + ",\"psx\": " + to_string(this-> psx)
    + ",\"pvn\": " + to_string(this-> pvn)
    + ",\"pvx\": " + to_string(this-> pvx)
    + ",\"thn\": " + to_string(this-> thn)
    + ",\"thx\": " + to_string(this-> thx)
    + ",\"tsn\": " + to_string(this-> tsn)
    + ",\"tsx\": " + to_string(this-> tsx)
    + ",\"tvn\": " + to_string(this-> tvn)
    + ",\"tvx\": " + to_string(this-> tvx)
    + "," + json + "}";

  //发送数据
  string _send_data = to_string(json.length()) + "|" + to_string(base64_img.length()) + "|" + json + base64_img;
  ::send(client_sockfd, _send_data.c_str(), _send_data.size(), 0);
}

void sys::close(){
  if (client_sockfd < 0) return;

  //close(client_sockfd);

}