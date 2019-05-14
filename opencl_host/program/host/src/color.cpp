#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <cstring>
#include <CL/opencl.h>
#include "AOCLUtils/aocl_utils.h"
#include <float.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include "opt.h"
#include "Parameter.h"

using namespace aocl_utils;
#define STRING_BUFFER_LEN 1024

cl_uchar *host_input;
cl_uchar *host_output;
cl_uchar *host_gray;

static cl_int status;
// OpenCL runtime configuration
static cl_platform_id platform = NULL;
static cl_device_id device = NULL;
static cl_context context = NULL;
static cl_command_queue queue = NULL;
static cl_kernel kernel = NULL;
static cl_program program = NULL;

static cl_mem buf_rgb;
static cl_mem buf_gray;
static cl_mem buf_yuyv;

static unsigned int width;
static unsigned int height;
static unsigned int srcStride;
static unsigned int dstStride;

static unsigned char cl_h_min;
static unsigned char cl_h_max;
static unsigned char cl_s_min;
static unsigned char cl_s_max;
static unsigned char cl_v_min;
static unsigned char cl_v_max;

extern options opt;

template <typename T>
cl_mem alloc_shared_buffer(size_t size, T **host_ptr)
{
	cl_int status;
	cl_mem device_ptr = clCreateBuffer(context, CL_MEM_ALLOC_HOST_PTR, sizeof(T) * size, NULL, &status);
	checkError(status, "Failed to create buffer");
	assert(host_ptr != NULL);
	*host_ptr = (T *)clEnqueueMapBuffer(queue, device_ptr, CL_TRUE, CL_MAP_WRITE | CL_MAP_READ, 0, sizeof(T) * size, 0, NULL, NULL, NULL);
	assert(*host_ptr != NULL);
	// populate the buffer with garbage data
	return device_ptr;
}

bool init_opencl()
{

	width = opt.width;
	height = opt.height;
	srcStride = width * 2;
	dstStride = width * 3;
	if (!setCwdToExeDir())
	{
		return false;
	}

	platform = findPlatform("Intel");
	if (platform == NULL)
	{
		printf("ERROR: Unable to find IntelFPGA OpenCL platform.\n");
		return false;
	}

	// User-visible output - Platform information
	char char_buffer[STRING_BUFFER_LEN];
	printf("Querying platform for info:\n");
	printf("==========================\n");
	clGetPlatformInfo(platform, CL_PLATFORM_NAME, STRING_BUFFER_LEN, char_buffer, NULL);
	printf("%-40s = %s\n", "CL_PLATFORM_NAME", char_buffer);
	clGetPlatformInfo(platform, CL_PLATFORM_VENDOR, STRING_BUFFER_LEN, char_buffer, NULL);
	printf("%-40s = %s\n", "CL_PLATFORM_VENDOR ", char_buffer);
	clGetPlatformInfo(platform, CL_PLATFORM_VERSION, STRING_BUFFER_LEN, char_buffer, NULL);
	printf("%-40s = %s\n\n", "CL_PLATFORM_VERSION ", char_buffer);

	// Query the available OpenCL devices.
	scoped_array<cl_device_id> devices;
	cl_uint num_devices;

	devices.reset(getDevices(platform, CL_DEVICE_TYPE_ALL, &num_devices));

	// We'll just use the first device.
	device = devices[0];

	// Create the context.
	context = clCreateContext(NULL, 1, &device, NULL, NULL, &status);
	checkError(status, "Failed to create context");

	// Create the command queue.
	queue = clCreateCommandQueue(context, device, CL_QUEUE_PROFILING_ENABLE, &status);
	checkError(status, "Failed to create command queue");

	// Create the program.
	std::string binary_file = getBoardBinaryFile("YUYV2RGBHSV", device);
	printf("Using AOCX: %s\n", binary_file.c_str());
	program = createProgramFromBinary(context, binary_file.c_str(), &device, 1);

	// Build the program that was just created.
	status = clBuildProgram(program, 0, NULL, "", NULL, NULL);
	checkError(status, "Failed to build program");

	// Create the kernel - name passed in here must match kernel name in the
	// original CL file, that was compiled into an AOCX file using the AOC tool
	const char *kernel_name = "YUYV2RGBHSV"; // Kernel name, as defined in the CL file
	kernel = clCreateKernel(program, kernel_name, &status);
	checkError(status, "Failed to create kernel");

	host_input = (cl_uchar *)alignedMalloc(width * height * 2 * sizeof(unsigned char));
	host_output = (cl_uchar *)alignedMalloc(width * height * 3 * sizeof(unsigned char));
	host_gray = (cl_uchar *)alignedMalloc(width * height * sizeof(unsigned char));

	//hw_output = (cl_uchar *)alignedMalloc(width * height * 3 * sizeof(unsigned char));

	buf_yuyv = alloc_shared_buffer<unsigned char>(width * height * 2 * sizeof(unsigned char), &host_input);
	buf_rgb = alloc_shared_buffer<unsigned char>(width * height * 3 * sizeof(unsigned char), &host_output);
	buf_gray = alloc_shared_buffer<unsigned char>(width * height * sizeof(unsigned char), &host_gray);

	status = clSetKernelArg(kernel, 1, sizeof(int), &srcStride);
	status = clSetKernelArg(kernel, 2, sizeof(int), &dstStride);
	status = clSetKernelArg(kernel, 3, sizeof(cl_mem), &buf_rgb);
	status = clSetKernelArg(kernel, 4, sizeof(cl_mem), &buf_gray);
	return true;
}

// Free the resources allocated during initialization
void cleanup()
{
	// Free the resources allocated
	if (host_input)
	{
		clEnqueueUnmapMemObject(queue, buf_yuyv, host_input, 0, NULL, NULL);
		clReleaseMemObject(buf_yuyv);
		host_input = 0;
	}
	if (host_output)
	{
		clEnqueueUnmapMemObject(queue, buf_rgb, host_output, 0, NULL, NULL);
		clReleaseMemObject(buf_rgb);
		host_output = 0;
	}
	if (host_gray)
	{
		clEnqueueUnmapMemObject(queue, buf_gray, host_gray, 0, NULL, NULL);
		clReleaseMemObject(buf_gray);
		host_gray = 0;
	}

	if (kernel)
	{
		clReleaseKernel(kernel);
	}
	if (program)
	{
		clReleaseProgram(program);
	}
	if (queue)
	{
		clReleaseCommandQueue(queue);
	}
	if (context)
	{
		clReleaseContext(context);
	}
}

void yuyv2rgb_hw(const void *ptr, unsigned char h_min, unsigned char h_max, unsigned char s_min, unsigned char s_max, unsigned char v_min, unsigned char v_max)
{
	cl_ulong start, end;
	cl_event event;
	double time_ms;
	unsigned char *data = (unsigned char *)ptr;
	cl_h_min = h_min;
	cl_h_max = h_max;
	cl_s_min = s_min;
	cl_s_max = s_max;
	cl_v_min = v_min;
	cl_v_max = v_max;
	status = clEnqueueWriteBuffer(queue, buf_yuyv, CL_TRUE, 0, width * height * 2 * sizeof(unsigned char), data, 0, NULL, NULL);
	status = clSetKernelArg(kernel, 0, sizeof(cl_mem), &buf_yuyv);
	status = clSetKernelArg(kernel, 5, sizeof(char), &cl_h_min);
	status = clSetKernelArg(kernel, 6, sizeof(char), &cl_h_max);
	status = clSetKernelArg(kernel, 7, sizeof(char), &cl_s_min);
	status = clSetKernelArg(kernel, 8, sizeof(char), &cl_s_max);
	status = clSetKernelArg(kernel, 9, sizeof(char), &cl_v_min);
	status = clSetKernelArg(kernel, 10, sizeof(char), &cl_v_max);
	// Configure work set over which the kernel will execute
	size_t globalSize[] = {width / 2, height, 0};
	size_t localSize[] = {1, 1, 1};
	// Launch the kernel
	status = clEnqueueNDRangeKernel(queue, kernel, 2, NULL, globalSize, localSize, 0, NULL, &event);
	//checkError(status, "Failed to launch kernel");
	status = clFinish(queue);
	checkError(status, "\nKernel Failed to finish");
	status = clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_START, sizeof(cl_ulong), &start, NULL);
	status |= clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_END, sizeof(cl_ulong), &end, NULL);
	checkError(status, "Error: could not get profile information");
	clReleaseEvent(event);
	time_ms = (end - start) * 1e-6f;
	printf("&<Kernel run time>-->%.3lf ms.\r\n", time_ms);
}
