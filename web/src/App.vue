<template>
  <div class="app-container">
    <h1>基于FPGA的图像识别系统的设计</h1>
    <el-row class="cvcl-row">
      <el-button
        :type="serverStatusTest[serverStatus].b"
        @click="tapServerStatus"
        round
        :circle="serverStatus == 1"
        :icon="serverStatusTest[serverStatus].i"
      >
        <template v-if="serverStatus != 1">{{ serverStatusTest[serverStatus].t }}</template>
      </el-button>

      <el-button type="text" v-if="serverStatus != 1" @click="tapServerConfig">服务器设置</el-button>

      <template v-if="serverStatus == 1">
        <el-button @click="auth" icon="el-icon-setting" v-if="!token" plain circle></el-button>

        <template v-else>
          <!-- 管理模式控制按钮 -->
          <el-dropdown @command="changeStep">
            <el-button round type="primary">
              {{ step[info.o] }}
              <i class="el-icon-arrow-down el-icon--right"></i>
            </el-button>
            <el-dropdown-menu slot="dropdown">
              <el-dropdown-item v-for="(value, key) in step" :key="key" :command="key">{{value}}</el-dropdown-item>
            </el-dropdown-menu>
          </el-dropdown>
        </template>
      </template>
    </el-row>

    <el-row class="cvcl-row" v-if="serverStatus == 1">
      <el-tag>{{ step[info.o] }}</el-tag>
      <el-tag type="success" v-if="info.result != ''">{{ info.result }}</el-tag>
      <el-tag v-if="false">FPS:{{ fps }}ms</el-tag>
    </el-row>

    <el-row class="cvcl-row" v-if="settingHSV == 1">
      <el-card class="setting_HSV" shadow="always">
        <div v-if="settingHSVType == 1">
          <el-row>
            <el-col :span="4">H</el-col>
            <el-col class="hsv" :span="20">
              <el-slider
                v-model="settingHSV_temp.p_h"
                range
                show-stops
                :max="180"
                @change="changeHSV"
              ></el-slider>
            </el-col>
          </el-row>
          <el-row>
            <el-col :span="4">S</el-col>
            <el-col :span="20">
              <el-slider
                v-model="settingHSV_temp.p_s"
                range
                show-stops
                :max="255"
                @change="changeHSV"
              ></el-slider>
            </el-col>
          </el-row>
          <el-row>
            <el-col :span="4">V</el-col>
            <el-col :span="20">
              <el-slider
                v-model="settingHSV_temp.p_v"
                range
                show-stops
                :max="255"
                @change="changeHSV"
              ></el-slider>
            </el-col>
          </el-row>
        </div>
        <div v-if="settingHSVType == 2">
          <el-row>
            <el-col :span="4">H</el-col>
            <el-col class="hsv" :span="20">
              <el-slider
                v-model="settingHSV_temp.t_h"
                range
                show-stops
                :max="180"
                @change="changeHSV"
              ></el-slider>
            </el-col>
          </el-row>
          <el-row>
            <el-col :span="4">S</el-col>
            <el-col :span="20">
              <el-slider
                v-model="settingHSV_temp.t_s"
                range
                show-stops
                :max="255"
                @change="changeHSV"
              ></el-slider>
            </el-col>
          </el-row>
          <el-row>
            <el-col :span="4">V</el-col>
            <el-col :span="20">
              <el-slider
                v-model="settingHSV_temp.t_v"
                range
                show-stops
                :max="255"
                @change="changeHSV"
              ></el-slider>
            </el-col>
          </el-row>
        </div>
        <el-row>
          <el-button icon="el-icon-close" size="mini" circle @click="settingHSV = false"></el-button>
        </el-row>
      </el-card>
    </el-row>

    <el-row class="cvcl-row" v-contextmenu:contextmenu v-if="serverStatus == 1">
      <img class="image" v-if="image" :src="image">

      <img class="image" v-else src="./assets/logo.png">
    </el-row>
    <el-row class="cvcl-row" v-else>
      <img class="logo" src="./assets/logo.png">
    </el-row>

    <v-contextmenu ref="contextmenu">
      <v-contextmenu-item @click="tapSettingHSV(1)">调整第一次HSV设置</v-contextmenu-item>
      <v-contextmenu-item @click="tapSettingHSV(2)">调整第二次HSV设置</v-contextmenu-item>
    </v-contextmenu>
  </div>
</template>

<script>
import md5 from "js-md5"; //引入md5库

export default {
  name: "index",
  data() {
    return {
      wsuri: "ws://192.168.15.5:8888/websocket", 
      image: "", //存放图片
      info: {
        //从服务器发来的信息
        o: 0, //处理步骤
        result: "",
        phn: 80,
        phx: 120,
        psn: 150,
        psx: 255,
        pvn: 0,
        pvx: 255,
        thn: 0,
        thx: 180,
        tsn: 0,
        tsx: 90,
        tvn: 210,
        tvx: 255
      },
      token: "", //管理模式密钥abc123
      settingHSV: 0, //设置HSV模式
      settingHSV_temp: [], //设置HSV模式临时储存数据
      step: {
        //处理步骤
        0: "处理结果",
        1: "原图",
        2: "原图进行HSV变换",
        3: "获得车牌遮罩",
        4: "车牌图像",
        5: "对车牌进行HSV变换",
        6: "形态学转换"
      },

      websock: null, //websocket

      time: 0, //上一次图片传过来的时间,用于计算fps
      fps: 0,

      serverStatus: -1, //-1连接失败 0连接中 1连接成功
      serverStatusTest: {
        "-1": {
          t: "连接失败,点击重试", //按钮显示文字
          b: "danger", //按钮样式
          i: "el-icon-error" //图标
        },
        "0": {
          t: "连接中",
          b: "primary",
          i: "el-icon-loading" //图标
        },
        "1": {
          t: "",
          b: "success",
          i: "el-icon-success" //图标
        }
      }
    };
  },

  created() {
    this.initWebSocket();
  },
  destroyed() {
    this.websock.close(); //离开路由之后断开websocket连接
  },
  methods: {
    handleSelect(key, keyPath) {
      console.log(key, keyPath);
    },
    initWebSocket() {
      //初始化weosocket
      this.serverStatus = 0;
      this.websock = new WebSocket(this.wsuri);
      this.websock.onmessage = this.websocketonmessage;
      this.websock.onopen = this.websocketonopen;
      this.websock.onerror = this.websocketonerror;
      this.websock.onclose = this.websocketclose;
    },
    websocketonopen() {
      //连接建立之后执行send方法发送数据
      this.serverStatus = 1;
      this.$message({
        message: "与服务器连接成功",
        type: "success"
      });
      //let actions = { test: "12345" };
      //this.websocketsend(JSON.stringify(actions));
    },
    websocketonerror() {
      //连接建立失败
    },
    websocketonmessage(e) {
      //数据接收
      if (e.data.slice(0, 1) == "{") {
        const _info = JSON.parse(e.data);
        console.log(_info);
        if (_info["type"] == "python") {
          //从python发来的指令
          if (_info["state"] == 1) {
            if (_info["code"] == 1000) {
              this.token = _info["token"];
              this.$notify({
                title: "密码鉴定成功",
                message: "您可以自由的使用管理工具",
                type: "success"
              });
            }
          } else
            this.$notify({
              title: "错误",
              message: _info["message"],
              type: "warning"
            });
        } else {
          var _text = this.info.result;
          this.info = _info;
          if (
            _info.o == 0 &&
            _info.result != "找不到车牌" &&
            _info.result == ""
          ) {
            this.info.result = _text;
          }
        }
      } else if (e.data.slice(0, 11) == "data:image/") {
        this.image = e.data;
        //计算fps
        var timestamp = new Date().getTime();
        console.log(timestamp);
        this.fps = timestamp - this.time;
        this.time = timestamp;
      }
    },
    websocketsend(Data) {
      //数据发送
      this.websock.send(Data);
    },
    websocketclose(e) {
      //关闭
      var that = this;
      this.serverStatus = -1;
      this.$message("与服务器断开连接");
      this.token = "";
      this.websocketonerror();
    },

    tapSettingHSV(a) {
      //点击更改HSV设置按钮
      if (this.token) {
        const info = this.info;
        this.settingHSV_temp = {
          p_h: [info.phn, info.phx],
          p_s: [info.psn, info.psx],
          p_v: [info.pvn, info.pvx],

          t_h: [info.thn, info.thx],
          t_s: [info.tsn, info.tsx],
          t_v: [info.tvn, info.tvx]
        };
        this.settingHSVType = a;
        this.settingHSV = 1; //设置HSV模式
      }
    },

    tapServerStatus() {
      //点击连接服务器
      if (this.serverStatus == -1)
        //连接失败状态
        this.initWebSocket();
      else if (this.serverStatus == 1) this.websocketclose();
    },
    tapServerConfig() {
      var that = this;
      this.$prompt("请输入服务器地址", "提示", {
        confirmButtonText: "确定",
        cancelButtonText: "取消",
        inputPlaceholder: "*.com"
      })
        .then(({ value }) => {
          if (!value) value = "*.com";
          that.wsuri = "ws://" + value;
          this.$message({
            type: "success",
            message: "设置成功: " + value
          });
          this.websock.close();
          this.initWebSocket();
        })
        .catch(() => {});
    },
    auth() {
      //开启管理页面
      this.$prompt("请输入管理密码", "开启管理控制台", {
        confirmButtonText: "提交验证",
        cancelButtonText: "取消",
        inputType: "password",
        inputPattern: /^[0-9a-zA-z_]{6,}$/,
        inputErrorMessage: "密码格式不正确"
      })
        .then(({ value }) => {
          this.websocketsend(
            JSON.stringify({
              password: md5("doaruno" + value + "kurumashikibetsu")
            })
          );
        })
        .catch(() => {});
    },
    changeHSV() {
      if (this.token) {
        this.websocketsend(
          JSON.stringify({
            token: this.token,
            phn: this.settingHSV_temp.p_h[0],
            phx: this.settingHSV_temp.p_h[1],
            psn: this.settingHSV_temp.p_s[0],
            psx: this.settingHSV_temp.p_s[1],
            pvn: this.settingHSV_temp.p_v[0],
            pvx: this.settingHSV_temp.p_v[1],

            thn: this.settingHSV_temp.t_h[0],
            thx: this.settingHSV_temp.t_h[1],
            tsn: this.settingHSV_temp.t_s[0],
            tsx: this.settingHSV_temp.t_s[1],
            tvn: this.settingHSV_temp.t_v[0],
            tvx: this.settingHSV_temp.t_v[1]
          })
        );
        //this.$message("click on item ");
      }
    },

    changeStep(command) {
      if (this.token) {
        this.websocketsend(
          JSON.stringify({
            token: this.token,
            o: parseInt(command)
          })
        );
        //this.$message("click on item " + command);
        this.info.o = command;
      }
    }
  }
};
</script>

<!-- Add "scoped" attribute to limit CSS to this component only -->
<style>
.app-container {
  text-align: center;
}
.cvcl-row {
  margin-bottom: 10px;
}
h1 {
  margin-block-end: 0px;
}
h5 {
  margin-block-start: 0px;
  margin-block-end: 10px;
}

img {
  width: auto;
  height: auto;
  max-width: 100%;
  max-height: 100%;
}
.image {
  width: 600px;
  box-shadow: 0 0px 15px 0 rgba(0, 0, 0, 0.5);
  background-size: cover;
}
.setting_HSV {
  width: auto;
  max-width: 400px;
  margin-left: auto;
  margin-right: auto;
  line-height: 38px;
}
.setting_HSV .text {
}

.hsv .el-slider__bar{
  background-color: rgba(255,255,255,0);

}
.hsv .el-slider__runway{
  background-color: none;
  background-image: url("./assets/hsv.png");
  background-size: cover;
}
</style>

