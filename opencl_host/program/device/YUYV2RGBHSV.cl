unsigned char clamp_uc(int v, int l, int h)
{
    if (v > h)
        v = h;
    if (v < l)
        v = l;
    return (unsigned char)v;
}

void Rgb2Hsv(float R, float G, float B, float *H, float *S, float *V)
{
    // r,g,b values are from 0 to 1
    // h = [0,360], s = [0,1], v = [0,1]
    // if s == 0, then h = -1 (undefined)
    float min, max, delta, tmp;
    tmp = R > G ? G : R;
    min = tmp > B ? B : tmp;
    tmp = R > G ? R : G;
    max = tmp > B ? tmp : B;
    *V = max; // v
    delta = max - min;
    if (max != 0)
        *S = delta / max; // s
    else
    {
        // r = g = b = 0 // s = 0, v is undefined
        *S = 0;
        *H = 0;
        return;
    }
    if (delta == 0)
    {
        *H = 0;
        return;
    }
    else
    {
        if (R == max)
        {
            if (G >= B)
                *H = (G - B) / delta; // between yellow & magenta
            else
                *H = (G - B) / delta + 6.0;
        }
        else
        {
            if (G == max)
                *H = 2.0 + (B - R) / delta; // between cyan & yellow
            else
            {
                *H = 4.0 + (R - G) / delta;
            }
        }
    }
    *H *= 30.0; // degrees/2
    *S *= 255.0;
    *V *= 255.0;
}

unsigned char range(unsigned char h,unsigned char s,unsigned char v,
                    unsigned char *Hmin,unsigned char *Hmax,
                    unsigned char *Smin,unsigned char *Smax,
                    unsigned char *Vmin,unsigned char *Vmax)
{
    unsigned char tmp = 255;//80-120,150-255,0-255

    tmp = h > *Hmax ? 0 : tmp;
    tmp = h < *Hmin ? 0 : tmp;

    tmp = s > *Smax ? 0 : tmp;
    tmp = s < *Smin ? 0 : tmp;

    tmp = v > *Vmax ? 0 : tmp;
    tmp = v < *Vmin ? 0 : tmp;

    return tmp;
}

__kernel void YUYV2RGBHSV(	__global unsigned char *restrict yuyv,
							unsigned int srcStride,
							unsigned int dstStride,
							__global unsigned char *restrict rgb,
							__global unsigned char *restrict gray,
                            unsigned char Hi,
                            unsigned char Ha,
                            unsigned char Si,
                            unsigned char Sa,
                            unsigned char Vi,
                            unsigned char Va)
{
    int x = get_global_id(0) * 2; // extend the x-width since it is macropixel indexed
    int y = get_global_id(1);
    int y0,u0,y1,v0,r,g,b;
    float h,s,v;
    
    // determine yuyv index 
    int i = (y * srcStride) + (x * 2); // xstride == 2
    // determine rgb index
    int j = (y * dstStride) + (x * 3); // xstride == 3
	
    int k = (y * srcStride>>1) + x; // xstride == 1
	
	y0 = yuyv[i+0] - 16;
	u0 = yuyv[i+1] - 128;
    y1 = yuyv[i+2] - 16;
    v0 = yuyv[i+3] - 128;
    
   //part 1
    r = clamp_uc(((74 * y0) + (102 * v0)) >> 6 ,0,255); 
    g = clamp_uc(((74 * y0) - (52 * v0) - (25 * u0)) >> 6,0,255);
    b = clamp_uc(((74 * y0) + (129 * u0)) >> 6,0,255);

    rgb[j + 0] = b;
    rgb[j + 1] = g;
    rgb[j + 2] = r;

    Rgb2Hsv(r,g,b,&h,&s,&v);
    gray[k + 0] = range((unsigned char)h,(unsigned char)s,(unsigned char)v,&Hi,&Ha,&Si,&Sa,&Vi,&Va);

    //part2
	r = clamp_uc(((74 * y1) + (102 * v0)) >> 6 ,0,255); 
    g = clamp_uc(((74 * y1) - (52 * v0) - (25 * u0)) >> 6,0,255);
    b = clamp_uc(((74 * y1) + (129 * u0)) >> 6,0,255);
    
    rgb[j + 3] = b;
    rgb[j + 4] = g;
    rgb[j + 5] = r;

    Rgb2Hsv(r,g,b,&h,&s,&v);
    gray[k + 1] = range((unsigned char)h,(unsigned char)s,(unsigned char)v,&Hi,&Ha,&Si,&Sa,&Vi,&Va);
}