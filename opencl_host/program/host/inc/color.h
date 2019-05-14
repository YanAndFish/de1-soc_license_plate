#ifndef COLOR_H
#define COLOR_H

bool init_opencl();
void yuyv2rgb_hw(const void *ptr, unsigned char h_min, unsigned char h_max, unsigned char s_min, unsigned char s_max, unsigned char v_min, unsigned char v_max);
void cleanup();

#endif
