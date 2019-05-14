#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <assert.h>
#include "video.h"
#include "color.h"
#include "opt.h"
#include "Parameter.h"

#define BUFFER_NUM 1

static int stream_flag = V4L2_BUF_TYPE_VIDEO_CAPTURE;

extern unsigned char *host_input;  //opencl��������ָ��
extern unsigned char *host_output; //opencl�������ָ��?
unsigned char *surface_output;
struct video video;
extern options opt;

static void video_open();
static void video_close();
static void video_set_format();
static void video_streamon();
static void video_streamoff();
static void buffer_init();
static void buffer_free();
static void buffer_request();
static void video_capability();
static void yuv2rgb(unsigned char Y, unsigned char Cb, unsigned char Cr, int *ER, int *EG, int *EB);
static void update_rgb_pixels(const void *start);
static int clamp(double x);

static void video_capability()
{
	int ret = -1;
	struct v4l2_capability cap;
	ret = ioctl(video.fd, VIDIOC_QUERYCAP, &cap);
	if (ret < 0)
	{
		perror("ioctl");
		exit(-1);
	}
	printf("%s \n%s\n%s\n %08x %08x\n", cap.driver, cap.card, cap.bus_info, cap.version, cap.capabilities);
	printf("V4L2_CAP_VIDEO_CAPTURE = %08x    %d \n", V4L2_CAP_VIDEO_CAPTURE, V4L2_CAP_VIDEO_CAPTURE & cap.capabilities);
	if (!(V4L2_CAP_VIDEO_CAPTURE & cap.capabilities))
	{
		perror("capture not support");
		exit(-1);
	}
}

static void video_open()
{
	int i, fd;
	char device[13];

	for (i = 0; i < 99; i++)
	{
		sprintf(device, "%s%d", "/dev/video", i);
		fd = open(device, O_RDWR);
		if (fd != -1)
		{
			printf("open %s success\n", device);
			break;
		}
	}

	if (i == 100)
	{
		perror("video open fail");
		exit(EXIT_FAILURE);
	}

	video.fd = fd;
}

static void video_close()
{
	close(video.fd);
}

static void video_set_format() //���õ�ǰ������Ƶ������?
{
	memset(&video.format, 0, sizeof(video.format));
	//video.format.type = stream_flag;
	video.format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	video.format.fmt.pix.width = opt.width;
	video.format.fmt.pix.height = opt.height;
	video.format.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
	if (ioctl(video.fd, VIDIOC_S_FMT, &video.format) == -1)
	{
		perror("VIDIOC_S_FORMAT");
		exit(EXIT_FAILURE);
	}
}

static void video_streamon() //��Ƶ����ʼ
{
	if (ioctl(video.fd, VIDIOC_STREAMON, &stream_flag) == -1)
	{
		if (errno == EINVAL)
		{
			perror("streaming i/o is not support");
		}
		else
		{
			perror("VIDIOC_STREAMON");
		}
		exit(EXIT_FAILURE);
	}
}

static void video_streamoff() //��Ƶ������
{
	if (ioctl(video.fd, VIDIOC_STREAMOFF, &stream_flag) == -1)
	{
		if (errno == EINVAL)
		{
			perror("streaming i/o is not support");
		}
		else
		{
			perror("VIDIOC_STREAMOFF");
		}
		exit(EXIT_FAILURE);
	}
}

static void buffer_init()
{
	int i;

	buffer_request();
	for (i = 0; i < (int)video.buffer.req.count; i++) //���buffer
	{
		buffer_mmap(i);
		buffer_enqueue(i);
	}

	surface_output = (unsigned char *)malloc(opt.height * opt.width * 3); //�?件�?�理缓冲�?
	memset(surface_output, 0, (opt.height * opt.width * 3));
}

static void buffer_free()
{
	int i;

	for (i = 0; i < (int)video.buffer.req.count; i++)
	{
		munmap(video.buffer.buf[i].start, video.buffer.buf[i].length);
	}
	free(video.buffer.buf);
}

static void buffer_request()
{

	memset(&video.buffer.req, 0, sizeof(video.buffer.req));
	//video.buffer.req.type = stream_flag;
	video.buffer.req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	video.buffer.req.memory = V4L2_MEMORY_MMAP;
	video.buffer.req.count = BUFFER_NUM;
	/* ������Ƶ֡������ */
	if (ioctl(video.fd, VIDIOC_REQBUFS, &video.buffer.req) == -1)
	{
		if (errno == EINVAL)
		{
			perror("video capturing or mmap-streaming is not support");
		}
		else
		{
			perror("VIDIOC_REQBUFS");
		}
		exit(EXIT_FAILURE);
	}

	if (video.buffer.req.count < BUFFER_NUM)
	{
		perror("no enough buffer");
		exit(EXIT_FAILURE);
	}
	video.buffer.buf = (buf *)calloc(video.buffer.req.count, sizeof(*video.buffer.buf));

	assert(video.buffer.buf != NULL);
}

void buffer_mmap(int index)
{
	memset(&video.buffer.query, 0, sizeof(video.buffer.query));
	video.buffer.query.type = video.buffer.req.type;
	video.buffer.query.memory = V4L2_MEMORY_MMAP;
	video.buffer.query.index = index;
	/* ��Ƶ֡����ӳ�䵽video.fd */
	if (ioctl(video.fd, VIDIOC_QUERYBUF, &video.buffer.query) == -1)
	{
		perror("VIDIOC_QUERYBUF");
		exit(EXIT_FAILURE);
	}
#if HW
	video.buffer.buf[index].length = video.buffer.query.length;
	host_input = (unsigned char *)mmap(NULL,
									   video.buffer.query.length,
									   PROT_READ | PROT_WRITE,
									   MAP_SHARED,
									   video.fd,
									   video.buffer.query.m.offset);
#else
	video.buffer.buf[index].start = mmap(NULL,
										 video.buffer.query.length,
										 PROT_READ | PROT_WRITE,
										 MAP_SHARED,
										 video.fd,
										 video.buffer.query.m.offset);
#endif
	if (video.buffer.buf[index].start == MAP_FAILED)
	{
		perror("mmap");
		exit(EXIT_FAILURE);
	}
}

void video_init()
{
	video_open();
	video_capability();
	video_set_format();
	buffer_init();
	video_streamon();
}

void video_quit()
{
	video_streamoff();
	video_close();
	buffer_free();
}

void buffer_enqueue(int index)
{
	memset(&video.buffer.query, 0, sizeof(video.buffer.query)); //��buffer
	video.buffer.query.type = video.buffer.req.type;
	video.buffer.query.memory = V4L2_MEMORY_MMAP;
	video.buffer.query.index = index;
	/* ��Ƶ֡�������? */
	if (ioctl(video.fd, VIDIOC_QBUF, &video.buffer.query) == -1)
	{
		perror("VIDIOC_QBUF");
		exit(EXIT_FAILURE);
	}
}

void buffer_dequeue(int index)
{
	memset(&video.buffer.query, 0, sizeof(video.buffer.query)); //��buffer
	video.buffer.query.type = video.buffer.req.type;
	video.buffer.query.memory = V4L2_MEMORY_MMAP;
	video.buffer.query.index = index;
	/* ��Ƶ֡�������? */
	if (ioctl(video.fd, VIDIOC_DQBUF, &video.buffer.query) == -1)
	{
		perror("VIDIOC_DQBUF");
		exit(EXIT_FAILURE);
	}

#if 0
	printf("video.buffer.query.index:%d\n", video.buffer.query.index);
	printf("video.buffer.query.type:0x%x\n", video.buffer.query.type);
	printf("video.buffer.query.bytesused:%d\n", video.buffer.query.bytesused);
	printf("video.buffer.query.flags:0x%x\n", video.buffer.query.flags);
	printf("video.buffer.query.length:%d\n", video.buffer.query.length);
#endif
}

void video_get_hw()
{
	for (int i = 0; i < (int)video.buffer.req.count; i++) //�����ж����Ƶ��������ֱ�������������
	{
		buffer_dequeue(i);
		//_time("video buffer on");
		//yuyv2rgb_hw(host_input);
		//_time("run OpenCL(YUYV->RGB)");
		buffer_enqueue(i);
		//_time("video buffer off");
	}
}

void video_get_surface()
{
	//for (int i = 0; i < (int)video.buffer.req.count; i++) //�����ж����Ƶ��������ֱ�������������
	//{
		//buffer_dequeue(i);
		update_rgb_pixels(video.buffer.buf[0].start);
		//buffer_enqueue(i);
	//}
}

static void update_rgb_pixels(const void *start)
{
	unsigned char *data = (unsigned char *)start;
	unsigned char *pixels = surface_output;
	int width = opt.width;
	int height = opt.height;
	unsigned char Y, Cr, Cb;
	int r, g, b;
	int x, y;
	int p1, p2, p3, p4;

	for (y = 0; y < height; y++)
	{
		for (x = 0; x < width; x++)
		{
			p1 = y * width * 2 + x * 2;
			Y = data[p1];
			if (x % 2 == 0)
			{
				p2 = y * width * 2 + (x * 2 + 1);
				p3 = y * width * 2 + (x * 2 + 3);
			}
			else
			{
				p2 = y * width * 2 + (x * 2 - 1);
				p3 = y * width * 2 + (x * 2 + 1);
			}
			Cb = data[p2];
			Cr = data[p3];
			yuv2rgb(Y, Cb, Cr, &r, &g, &b);
			p4 = y * width * 3 + x * 3;
			pixels[p4] = b;
			pixels[p4 + 1] = g;
			pixels[p4 + 2] = r;
		}
	}
}

static void yuv2rgb(unsigned char Y,
					unsigned char Cb,
					unsigned char Cr,
					int *ER,
					int *EG,
					int *EB)
{
	double y1, pb, pr, r, g, b;

	y1 = (255 / 219.0) * (Y - 16);
	pb = (255 / 224.0) * (Cb - 128);
	pr = (255 / 224.0) * (Cr - 128);
	r = 1.0 * y1 + 0 * pb + 1.402 * pr;
	g = 1.0 * y1 - 0.344 * pb - 0.714 * pr;
	b = 1.0 * y1 + 1.722 * pb + 0 * pr;
	*ER = clamp(r);
	*EG = clamp(g);
	*EB = clamp(b);
}

static int clamp(double x)
{
	int r = x;
	if (r < 0)
		return 0;
	else if (r > 255)
		return 255;
	else
		return r;
}