/*
 * Note that the device and listener should be run with the same port and IP.
 * For example:
 *
 *  xrun --xscope-realtime --xscope-port 127.0.0.1:12346 ...
 *
 *  ./packet_analyser -s 127.0.0.1 -p 12346
 *
 */
/*
 * Includes for thread support
 */
#ifdef _WIN32
#include <winsock.h>

int file_exists(char *filename)
{
  WIN32_FIND_DATA FindFileData;
  HANDLE handle = FindFirstFile(filename, &FindFileData);
  if (handle != INVALID_HANDLE_VALUE) {
    FindClose(handle);
    return 1;
  } else {
    return 0;
  }
}

#else

#include <pthread.h>
#include <unistd.h>

int file_exists(char *filename)
{
  if (access(filename, F_OK) != -1)
    return 1;
  else
    return 0;
}
#endif


#include "xscope_host_shared.h"
#include "host_xscope.h"

#define MAX_FILENAME_LEN 1024

const char *g_prompt = "";

/* Interface on which the glitch occurred */
int g_interface = 0;
/* Size of the data received */
int g_expected_words = 0;

/* The ID of the glitch probe determined from the registrations */
int g_glitch_probe = -1;

/* File is chosen on header reception */
FILE *g_file_handle = NULL;

void hook_registration_received(int sockfd, int xscope_probe, char *name)
{
  if (strcmp(name, "Audio Analyzer.Glitch Data") == 0) {
    printf("Glitch Probe Registration: %d\n", xscope_probe);
    g_glitch_probe = xscope_probe;
  }
}

void hook_data_received(int sockfd, int xscope_probe, void *data, int data_len)
{
  if (xscope_probe != g_glitch_probe)
    return;

  int i = 0;
  int *int_data = (int*)data;
  FILE *f = NULL;

  if (g_expected_words == 0) {
    char filename[MAX_FILENAME_LEN];
    int is_glitch = 0;
    char *basename = "";

    if (data_len != 8)
      print_and_exit("ERROR: Received %d bytes when expecting 8 with the length\n", data_len);
    g_expected_words = int_data[0] >> 8;
    g_interface = int_data[0] & 0x7f;
    is_glitch = (int_data[0] >> 7) & 0x1;
    basename = is_glitch ? "glitch" : "signal";

    printf("Host: received %s on interface %d\n", basename, g_interface);

    /* Create a unique glitch filename */
    do {
      sprintf(filename, "%s_%d_%d.csv", basename, g_interface, i);
      i++;
    } while (file_exists(filename));

    g_file_handle = fopen(filename, "a");
    if (g_file_handle == NULL)
      print_and_exit("ERROR: Failed to open file to write %s '%s'\n", basename, filename);


  } else {
    int data_words = data_len/4;
    g_expected_words -= data_words;
    if (g_expected_words < 0)
      print_and_exit("ERROR: expected words gone negative\n");

    for (i = 0; i < data_words; i++) {
      fprintf(g_file_handle, "%d, ", int_data[i]);
      if (i && ((i % 8) == 0))
        fprintf(g_file_handle, "\n");
      fflush(g_file_handle);
    }

    if (g_expected_words == 0) {
      printf("Host: received data\n");
      fclose(g_file_handle);
      g_file_handle = NULL;
    }

    // Send an acknowledge for the data received
    ((unsigned char *)data)[0] = HOST_ACK_DATA;
    xscope_ep_request_upload(sockfd, 1, data);
  }
}

void hook_exiting()
{
  // Do nothing
}

static char get_next_char(const char **buffer)
{
  const char *ptr = *buffer;
  int len = 0;
  while (*ptr && isspace(*ptr))
    ptr++;

  *buffer = ptr + 1;
  return *ptr;
}

static int convert_atoi_substr(const char **buffer)
{
  const char *ptr = *buffer;
  unsigned int value = 0;
  while (*ptr && isspace(*ptr))
    ptr++;

  if (*ptr == '\0')
    return 0;

  value = atoi((char*)ptr);

  while (*ptr && !isspace(*ptr))
    ptr++;

  *buffer = ptr;
  return value;
}

void print_console_usage()
{
  printf("Supported commands:\n");
  printf("  h|?     : print this help message\n");
  printf("  e a     : enable all channels\n");
  printf("  e <n>   : enable channel n\n");
  printf("  d a     : disable all channels\n");
  printf("  d <n>   : disable channel n\n");
  printf("  c <n> <freq> <glitch_count> <glitch_start> <glitch_period> : configure channel n\n");
  printf("  s <n>   : signal dump n\n");
  printf("  v <n> <volume> : configure the volume of channel n (volume 1..31)\n");
  printf("  b <n>   : set the base channel number (default 0)\n");
  printf("  q       : quit\n");
}

#define LINE_LENGTH 1024

/*
 * A separate thread to handle user commands to control the target.
 */
#ifdef _WIN32
DWORD WINAPI console_thread(void *arg)
#else
void *console_thread(void *arg)
#endif
{
  int sockfd = *(int *)arg;
  char buffer[LINE_LENGTH + 1];
  do {
    int i = 0;
    int c = 0;
    const char *ptr = NULL;
    char cmd = 0;

    for (i = 0; (i < LINE_LENGTH) && ((c = getchar()) != EOF) && (c != '\n'); i++)
      buffer[i] = tolower(c);
    buffer[i] = '\0';

    ptr = &buffer[0];
    cmd = get_next_char(&ptr);
    switch (cmd) {
      case 'q':
        print_and_exit("Done\n");
        break;

      case 'e': {
        char to_send[2];
        const char *prev = ptr;
        char next = get_next_char(&ptr);
        if (next == 'a') {
          to_send[0] = HOST_ENABLE_ALL;
        } else {
          to_send[0] = HOST_ENABLE_ONE;
          to_send[1] = convert_atoi_substr(&prev);
        }
        printf("Sending %d:%d\n", to_send[0], to_send[1]);
        xscope_ep_request_upload(sockfd, 2, (unsigned char *)&to_send);
        break;
      }

      case 'd': {
        char to_send[2];
        const char *prev = ptr;
        char next = get_next_char(&ptr);
        if (next == 'a') {
          to_send[0] = HOST_DISABLE_ALL;
        } else {
          to_send[0] = HOST_DISABLE_ONE;
          to_send[1] = convert_atoi_substr(&prev);
        }
        printf("Sending %d:%d\n", to_send[0], to_send[1]);
        xscope_ep_request_upload(sockfd, 2, (unsigned char *)&to_send);
        break;
      }

      case 's': {
        char to_send[2];
        to_send[0] = HOST_SIGNAL_DUMP_ONE;
        to_send[1] = convert_atoi_substr(&ptr);
        printf("Sending %d:%d\n", to_send[0], to_send[1]);
        xscope_ep_request_upload(sockfd, 2, (unsigned char *)&to_send);
        break;
      }

      case 'v': {
        char to_send[3];
        to_send[0] = HOST_SET_VOLUME;
        to_send[1] = convert_atoi_substr(&ptr);
        to_send[2] = convert_atoi_substr(&ptr);
        if (to_send[2] > 0 && to_send[2] < 32) {
          printf("Sending %d:%d:%d\n", to_send[0], to_send[1], to_send[2]);
          xscope_ep_request_upload(sockfd, 3, (unsigned char *)&to_send);
        } else {
          printf("Volume must be >0 and <32, %d given\n", to_send[2]);
        }
        break;
      }

      case 'c': {
        unsigned to_send[5];
        unsigned char *to_send_c = (unsigned char *)(&to_send[0]);
        to_send_c[0] = HOST_CONFIGURE_ONE;
        to_send_c[1] = convert_atoi_substr(&ptr);
        to_send[1] = convert_atoi_substr(&ptr);
        to_send[2] = convert_atoi_substr(&ptr);
        to_send[3] = convert_atoi_substr(&ptr);
        to_send[4] = convert_atoi_substr(&ptr);

        printf("Sending %d:%d\n", to_send_c[0], to_send_c[1]);
        xscope_ep_request_upload(sockfd, sizeof(to_send), (unsigned char *)&to_send);
        break;
      }

      case 'b': {
        char to_send[2];
        to_send[0] = HOST_SET_BASE;
        to_send[1] = convert_atoi_substr(&ptr);
        printf("Sending %d:%d\n", to_send[0], to_send[1]);
        xscope_ep_request_upload(sockfd, 2, (unsigned char *)&to_send);
        break;
      }

      case 'h':
      case '?':
        print_console_usage();
        break;

      default:
        printf("Unrecognised command '%s'\n", buffer);
        print_console_usage();
    }
  } while (1);

#ifdef _WIN32
  return 0;
#else
  return NULL;
#endif
}

void usage(char *argv[])
{
  printf("Usage: %s [-s server_ip] [-p port]\n", argv[0]);
  printf("  -s server_ip :   The IP address of the xscope server (default %s)\n", DEFAULT_SERVER_IP);
  printf("  -p port      :   The port of the xscope server (default %s)\n", DEFAULT_PORT);
  exit(1);
}

int main(int argc, char *argv[])
{
#ifdef _WIN32
  HANDLE thread;
#else
  pthread_t tid;
#endif
  char *server_ip = DEFAULT_SERVER_IP;
  char *port_str = DEFAULT_PORT;
  int err = 0;
  int sockfds[1] = {0};
  int c = 0;

  while ((c = getopt(argc, argv, "s:p:")) != -1) {
    switch (c) {
      case 's':
        server_ip = optarg;
        break;
      case 'p':
        port_str = optarg;
        break;
      case ':': /* -f or -o without operand */
        fprintf(stderr, "Option -%c requires an operand\n", optopt);
        err++;
        break;
      case '?':
        fprintf(stderr, "Unrecognized option: '-%c'\n", optopt);
        err++;
    }
  }
  if (optind < argc)
    err++;

  if (err)
    usage(argv);

  sockfds[0] = initialise_socket(server_ip, port_str);

  // Now start the console
#ifdef _WIN32
  thread = CreateThread(NULL, 0, console_thread, &sockfds[0], 0, NULL);
  if (thread == NULL)
    print_and_exit("ERROR: Failed to create console thread\n");
#else
  err = pthread_create(&tid, NULL, &console_thread, &sockfds[0]);
  if (err != 0)
    print_and_exit("ERROR: Failed to create console thread\n");
#endif

  handle_sockets(sockfds, 1);
  return 0;
}

