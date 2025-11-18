/* Converts any 24-bit BMP into a 60×60 MIF with 9-bit color (3 bits per channel). */

#include <stdio.h>
#include <stdlib.h>

#define COLS 60
#define ROWS 60
#define COLOR_DEPTH 9
#define RGB (COLOR_DEPTH / 3)

typedef unsigned char byte;

static FILE *fp;

struct pixel
{
    byte b, g, r;
};

int width, height;

/************** POWER FUNCTION **************/
int power(int base, int exp)
{
    if (exp == 0)
        return 1;
    if (exp & 1)
        return base * power(base, exp - 1);
    int t = power(base, exp >> 1);
    return t * t;
}

/************** READ BMP (24-BIT) **************/
int read_bmp(char *filename, byte **header, struct pixel **data)
{
    FILE *file = fopen(filename, "rb");
    if (!file)
        return -1;

    byte *head = malloc(54);
    fread(head, 1, 54, file);

    width = *(int *)(head + 18);
    height = *(int *)(head + 22);

    int size = width * height;

    struct pixel *pixels = malloc(size * sizeof(struct pixel));

    // BMP rows are padded to multiples of 4 bytes — proper reading:
    int row_padded = (width * 3 + 3) & (~3);
    byte *row_data = malloc(row_padded);

    for (int y = 0; y < height; y++)
    {
        fread(row_data, 1, row_padded, file);
        for (int x = 0; x < width; x++)
        {
            int idx = (height - 1 - y) * width + x;
            pixels[idx].b = row_data[x * 3 + 0];
            pixels[idx].g = row_data[x * 3 + 1];
            pixels[idx].r = row_data[x * 3 + 2];
        }
    }

    free(row_data);
    fclose(file);

    *header = head;
    *data = pixels;
    return 0;
}

/************** WRITE PIXEL TO MIF **************/
void write_pixel(int x, int y, int color)
{
    int addr = y * COLS + x;
    fprintf(fp, "%d : %X;\n", addr, color);
}

/************** SCALE + WRITE **************/
void draw_image(struct pixel *img)
{
    float scale_x = (float)width / COLS;
    float scale_y = (float)height / ROWS;

    char fname[80];
    sprintf(fname, "bmp_%d_%d.mif", COLS, COLOR_DEPTH);
    fp = fopen(fname, "w");

    fprintf(fp, "WIDTH=%d;\n", COLOR_DEPTH);
    fprintf(fp, "DEPTH=%d;\n\n", COLS * ROWS);
    fprintf(fp, "ADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\n");
    fprintf(fp, "CONTENT BEGIN\n");

    for (int y = 0; y < ROWS; y++)
    {
        for (int x = 0; x < COLS; x++)
        {

            int src_x = (int)(x * scale_x);
            int src_y = (int)(y * scale_y);

            if (src_x >= width)
                src_x = width - 1;
            if (src_y >= height)
                src_y = height - 1;

            struct pixel p = img[src_y * width + src_x];

            int r = p.r, g = p.g, b = p.b;
            int R, G, B;

            // 3 bits per channel
            R = r >> 5; // 0–255 → 0–7
            G = g >> 5;
            B = b >> 5;

            int color = (R << 6) | (G << 3) | B;

            write_pixel(x, (ROWS - 1 - y), color);
        }
    }

    fprintf(fp, "END;\n");
    fclose(fp);
}

/************** MAIN **************/
int main(int argc, char *argv[])
{
    if (argc < 2)
    {
        printf("Usage: bmp_to_mif <BMP file>\n");
        return 0;
    }

    byte *header;
    struct pixel *image;

    if (read_bmp(argv[1], &header, &image) < 0)
    {
        printf("ERROR: Cannot read BMP file\n");
        return 0;
    }
    printf("USING COLS=%d ROWS=%d\n", COLS, ROWS);

    draw_image(image);
    return 0;
}

/* This program translates a 24-bit-color bitmap (.bmp) file into a MIF file.
 *
 * 1. set COLS and ROWS to match the target memory
 * 2. set the COLOR_DEPTH to 3, 6, or 9
 * 3. Compile the code using WindowsMake.bat
 * 4. Run the program using
 *    ./bmp_to_mif.exe image.bmp
 *
 *    where image.bmp is any 24-bit-color bitmap image. The result is written to a new file
 *    called bmp_COLS_COLORDEPTH.mif. If the resolution of image.bmp is higher than
 *    COLS x ROWS, then the image will be scaled down appropriately. Also, the color
 *    will be scaled down from 24-bit to COLOR_DEPTH. If the original image has a lower
 *    resolution than COLS x ROWs, then the new image will be centered within the larger
 *    resolution, with the color depth still being scaled as needed.
 */

/*
#include <stdio.h>
#include <stdlib.h>

#define COLS 60
#define ROWS 60
#define COLOR_DEPTH 9
#define RGB COLOR_DEPTH / 3

static FILE *fp;

int power(int base, int exp)
{
   if (exp == 0)
       return 1;
   else if (exp % 2)
       return base * power(base, exp - 1);
   else
   {
       int temp = power(base, exp / 2);
       return temp * temp;
   }
}

typedef unsigned char byte;
// The dimensions of the image
int width, height;
int screen_x, screen_y;

struct pixel
{
   byte b;
   byte g;
   byte r;
};

// Read BMP file and extract the pixel values (store in data) and header (store in header)
// Data is data[0] = BLUE, data[1] = GREEN, data[2] = RED, data[3] = BLUE, etc...
int read_bmp(char *filename, byte **header, struct pixel **data)
{
   struct pixel *data_tmp;
   byte *header_tmp;
   FILE *file = fopen(filename, "rb");

   if (!file)
       return -1;

   // read the 54-byte header
   header_tmp = malloc(54 * sizeof(byte));
   fread(header_tmp, sizeof(byte), 54, file);

   // get height and width of image from the header
   width = *(int *)(header_tmp + 18);  // width is a 32-bit int at offset 18
   height = *(int *)(header_tmp + 22); // height is a 32-bit int at offset 22

   // Read in the image
   int size = width * height;
   data_tmp = malloc(size * sizeof(struct pixel));
   fread(data_tmp, sizeof(struct pixel), size, file); // read the data
   fclose(file);

   *header = header_tmp;
   *data = data_tmp;

   return 0;
}

void write_pixel(int x, int y, int color)
{
   int address;
   address = y * COLS + x;
   fprintf(fp, "%d : %X;\n", address, color);
}

// Write the image to a MIF
void draw_image(struct pixel *data)
{
   int x, y, stride_x, stride_y, i, j, vga_x, vga_y;
   int r, g, b, R, G, B, color;
   struct pixel(*image)[width] = (struct pixel(*)[width])data; // allow image[][]

   char file_name[80];
   sprintf(file_name, "bmp_%d_%d.mif", COLS, COLOR_DEPTH);
   fp = fopen(file_name, "w");
   fprintf(fp, "WIDTH=%d;\n", COLOR_DEPTH);
   fprintf(fp, "DEPTH=%d;\n\n", COLS * ROWS);
   fprintf(fp, "ADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\n\n");
   fprintf(fp, "CONTENT BEGIN\n");

   screen_x = COLS;
   screen_y = ROWS;

   // scale the image to fit the screen
   stride_x = (width > screen_x) ? width / screen_x : 1;
   stride_y = (height > screen_y) ? height / screen_y : 1;
   // scale proportionally (don't stretch the image)
   stride_y = (stride_x > stride_y) ? stride_x : stride_y;
   stride_x = (stride_y > stride_x) ? stride_y : stride_x;
   for (y = 0; y < height; y += stride_y)
   {
       for (x = 0; x < width; x += stride_x)
       {
           // find the average of the pixels being scaled down to the VGA resolution
           r = 0;
           g = 0;
           b = 0;
           for (i = 0; i < stride_y; i++)
           {
               for (j = 0; j < stride_x; ++j)
               {
                   r += image[y + i][x + j].r;
                   g += image[y + i][x + j].g;
                   b += image[y + i][x + j].b;
               }
           }
           r = r / (stride_x * stride_y);
           g = g / (stride_x * stride_y);
           b = b / (stride_x * stride_y);

           // each of r, g, b is an 8-bit value. Convert to the right color-depth
           if (RGB == 1)
           {
               R = r > 127 ? 1 : 0;
               G = g > 127 ? 1 : 0;
               B = b > 127 ? 1 : 0;
           }
           else if (RGB == 2)
           {
               R = r > 191 ? 3 : (r > 127 ? 2 : (r > 63 ? 1 : 0));
               G = g > 191 ? 3 : (g > 127 ? 2 : (g > 63 ? 1 : 0));
               B = b > 191 ? 3 : (b > 127 ? 2 : (b > 63 ? 1 : 0));
           }
           else if (RGB == 3)
           {
               R = r > 223 ? 7 : (r > 191 ? 6 : (r > 159 ? 5 : (r > 127 ? 4 : (r > 95 ? 3 : (r > 63 ? 2 : (r > 31 ? 1 : 0))))));
               G = g > 223 ? 7 : (g > 191 ? 6 : (g > 159 ? 5 : (g > 127 ? 4 : (g > 95 ? 3 : (g > 63 ? 2 : (g > 31 ? 1 : 0))))));
               B = b > 223 ? 7 : (b > 191 ? 6 : (b > 159 ? 5 : (b > 127 ? 4 : (b > 95 ? 3 : (b > 63 ? 2 : (b > 31 ? 1 : 0))))));
           }
           // now write the pixel color to the MIF
           color = (R << RGB * 2) | (G << RGB) | B;
           vga_x = x / stride_x;
           vga_y = y / stride_y;
           if (screen_x > width / stride_x) // center if needed
               write_pixel(vga_x + (screen_x - (width / stride_x)) / 2, (screen_y - 1) - vga_y, color);
           else if ((vga_x < screen_x) && (vga_y < screen_y))
               write_pixel(vga_x, (screen_y - 1) - vga_y, color);
       }
   }
   fprintf(fp, "END;\n");
   fclose(fp);
}

int main(int argc, char *argv[])
{
   struct pixel *image;
   byte *header;

   // Check inputs
   if (argc < 2)
   {
       printf("Usage: bmp_to_mif <BMP filename>\n");
       return 0;
   }
   // Open input image file (24-bit bitmap image)
   if (read_bmp(argv[1], &header, &image) < 0)
   {
       printf("Failed to read BMP\n");
       return 0;
   }
   screen_x = COLS;
   screen_y = ROWS;

   draw_image(image);

   return 0;
}
*/