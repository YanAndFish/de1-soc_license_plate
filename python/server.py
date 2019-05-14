from websocket_server import WebsocketServer #pip3 install websocket-server
import threading # 多线程
import time
import random # 随机数
import json
#TCP服务器
import socket, threading

# 创建Websocket Server
server = WebsocketServer(9999,'0.0.0.0') # 9999

# TCP       9998
# Websocket 9999

# 校验
password = "5cd00b7911c4e7ee0e92a02a868d1f52"
token = ['abc123']

fpga = {
  'sock' : 0,
  'addr' : 0
}

#程序配置
config = {}

#生成随机字符串
def ranstr(num):
  _H = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+=-_!@#$%^&*~'
  salt = ''
  for i in range(num):
    salt += random.choice(_H)
  return salt

#websocket 有新客户端连接
def new_client(client, server):
  pass
  print("Websocket new client ID:%d" % client['id'])

#websocket 有客户端断线
def client_left(client, server):
  print("Websocket client(%d) disconnection." % client['id'])

#websocket 收到消息
def message_received(client, server, message):
  _ip,_port = client['address']
  _json = json.loads(message)
  global config
  if 'token' in _json: # 管理模式的人
    #print("向FPGA发送"+message)
    print("Websocket client(%d:%s) Send: %s" % (client['id'] , _ip , message))
    #写入配置
    if 'phn' in _json:
      f = open('./config.json','w+')
      f.write(message)
      f.close()
      config = _json

    if fpga['sock'] != 0: fpga['sock'].send(message.encode())

  else:
    if 'password' in _json:
      _result = {}
      if _json['password'] == password:
        _new_token = ranstr(32)
        print ("Websocket client ID:%d Successful Password Authentication! token:%s" % (client['id'], _new_token))
        token.append(_new_token)
        _result = {
          'type':'python',
          'state':1,
          'message':'登陆成功',
          'code':1000,
          'token':_new_token
        }
      else:
        print ("Websocket client ID:%d Failed to authenticate by password." % (client['id']))
        _result = {
          'type':'python',
          'state':0,
          'message':'密码错误',
          'code':1000,
        }
      server.send_message(client,json.dumps(_result))

  #print('客户端(%d):%s' % (client['id'], message))

# tcp处理
def tcplink(sock, addr):
  print("Fpga on-line! %s:%s" % addr)
  # sock.send(b'Welcome!')
  fpga['sock'] = sock
  fpga['addr'] = addr
  # 一个数据包结构：
  # int json_len | int image_len | json  image

  global config
  sock.send(json.dumps(config).encode())

  while True:
    m_data = sock.recv(20) #等待接收信息
    if not m_data: break # 客户端断开了就会返回-1
    m_data = m_data.decode('utf-8') #编码一下
    try:
      #print(m_data)

      json_len = 0
      if m_data[:m_data.find('|')]:
        json_len = int(m_data[:m_data.find('|')]) #读取json数据包的长度
      else:
        raise Exception("数据头错误")
      m_data = m_data[m_data.find('|')+1:] #数据头去掉json数据包
      image_len = int(m_data[:m_data.find('|')]) #读取image数据包的长度

      #print('数据包长度:' + str(data_len))
      json_data = m_data[m_data.find('|')+1:] #防止数据头和数据包粘包,所以还是要把数据头剩余的部分保存了

      #print('读取json 长度:%d/%d' % (len(json_data),json_len))
      # 读取json
      while json_len > len(json_data): # 如果数据没读完就一直读下去
        m_data = sock.recv(json_len - len(json_data)) #读包
        if not m_data: raise Exception("客户端断开") # 客户端断开了就会返回-1
        json_data += m_data.decode('utf-8') #保存

      #t = threading.Thread(target=wensocket_send_all,args=(json_data,))
      #t.start()
      server.send_message_to_all(json_data) #转发到websocket

      #print('读取图片 长度:%d' % image_len)
      #读取图片
      image_data = ""
      while image_len > len(image_data): # 如果数据没读完就一直读下去
        _read_len = image_len - len(image_data)
        #print("读取 %d" % (image_len - len(image_data)))
        _read_len = 65535 if _read_len >= 65535 else _read_len

        m_data = sock.recv(_read_len) #读包
        #print("读取了%d" % len(m_data))
        if not m_data: raise Exception("客户端断开") # 客户端断开了就会返回-1
        image_data += m_data.decode('utf-8') #保存
      server.send_message_to_all(image_data) #转发到websocket
      #j = threading.Thread(target=wensocket_send_all,args=(image_data,))
      #j.start()
    except:
      print("错误")
      while sock.recv(65535): pass #把剩下的所有数据都读出来丢掉

  #客户端掉线
  while sock.recv(65535): pass
  fpga['sock'] = 0
  fpga['addr'] = 0
  sock.close() #关掉连接
  print("Fpga offline")
  #print('Connection from %s:%s closed.' % addr)

def wensocket_send_all (msg):
  print('发送数据 %s...' % msg[:10])
  server.send_message_to_all(msg) #转发到websocket


def setup_websocket():# websocket 初始化
  #事件绑定
  server.set_fn_new_client(new_client) # 有设备连接上了
  server.set_fn_client_left(client_left) # 断开连接
  server.set_fn_message_received(message_received)# 接收到信息

  # 开始监听
  server.run_forever()

def setup_tcp_server():
  # TCP Server
  s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

  # 监听端口:
  s.bind(('0.0.0.0', 9998))
  # 连接的最大数量
  s.listen(5)

  print('Waiting for connection...')

  #启动蛤哥的opencv
  #sp = subprocess.Popen(cmd, stdout = subprocess.PIPE, stderr = subprocess.PIPE) 

  while True:
    # 接受一个新连接:
    sock, addr = s.accept()
    # 创建新线程来处理TCP连接:
    t = threading.Thread(target=tcplink, args=(sock, addr))
    t.start()

def main():
  #加载配置  json.dumps(_result)
  global config
  f = open('./config.json','r')
  conf_json = f.read()
  try:
    config = json.loads(conf_json)
  except:
    pass
  f.close()

  # 创建新线程:
  t = threading.Thread(target=setup_websocket)
  t.start()

  d = threading.Thread(target=setup_tcp_server)
  d.start()

if __name__ == "__main__":
  main()
