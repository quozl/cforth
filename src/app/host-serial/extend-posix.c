// Extension routines

#include <stdio.h>
#include <poll.h>
#include <fcntl.h>
#include <string.h>
#include <termios.h>
#include <sys/ioctl.h>
#ifdef __APPLE__
#include <stdlib.h>
#include <glob.h>
#endif
#include <unistd.h>
#include "forth.h"

// #define BUFFERED_READ

#ifdef BUFFERED_READ
char buf[100];
char *bufp;
int nbuf;
#endif

#ifdef __APPLE__
int get_nth_port(cell portnum, char ** resbuf)
{
	glob_t g;
	int retval = 0;

	retval = glob("/dev/cu.usbserial*", 0, NULL, &g);
	if (retval !=0 )
		return -1;
	if (portnum >= g.gl_pathc)
		return -1;
	char * result = g.gl_pathv[portnum];
	size_t ressize = strlen(result);
	*resbuf = malloc(ressize+1);
	if (*resbuf == 0)
	{
		fprintf(stderr,"Out of memory in get_nth_port\n");
		return -1;
	}
	strcpy(*resbuf, result);
	globfree(&g);
	return 0;
}
#endif

cell
open_com(cell portnum)		// Open COM port
{
	struct termios kstate;
	int comfid;
#ifdef __APPLE__
	char *comname;

	//snprintf(comname, comname_len, "/dev/cu.usbserial-", portnum);
	comfid = get_nth_port(portnum, &comname);
	if (comfid < 0) {
		fprintf(stderr, "Unable to find a port with name like /dev/cu.usbserial*\n");
		return (cell)comfid;
	}
#else
	char comname[32];

	sprintf(comname, "/dev/ttyUSB%ld", portnum);
#endif
	printf("%s\n",comname);
	comfid = open(comname, O_RDWR, O_EXCL);
#ifdef __APPLE__
	free(comname);
#endif
	if (comfid < 0) {
		return (cell)comfid;
	}
	tcgetattr(comfid,&kstate);
	cfmakeraw(&kstate);
	cfsetospeed(&kstate, B115200);
	cfsetispeed(&kstate, B115200);
	kstate.c_cflag |= CLOCAL;
	kstate.c_cc[VTIME] = 1;                 /* Try for 1/10 second   */
	kstate.c_cc[VMIN] = 0;			/* Poll for character	 */

	tcsetattr(comfid, TCSANOW, &kstate);

#ifdef BUFFERED_READ
	nbuf = 0;
#endif

	return (cell)comfid;
}

cell
set_com_parity(cell comfid, cell parity)   // 'e', 'o', 'n'
{
	struct termios kstate;
	tcgetattr(comfid,&kstate);
	switch (parity) {
	case 'n':
		kstate.c_cflag &= ~PARENB;
		break;
	case 'o':
		kstate.c_iflag |= IGNPAR;
		kstate.c_iflag &= INPCK;
		kstate.c_cflag |= PARENB;
		kstate.c_cflag |= PARODD;
		break;
	case 'e':
		kstate.c_iflag |= IGNPAR;
		kstate.c_iflag &= INPCK;
		kstate.c_cflag |= PARENB;
		kstate.c_cflag &= ~PARODD;
		break;
        }
	tcsetattr(comfid, TCSAFLUSH, &kstate);
}

cell
set_modem_control(cell comfid, cell dtr, cell rts)
{
	int modemstat, modemstatold;
	
	ioctl(comfid, TIOCMGET, &modemstat);
	modemstatold = modemstat;
	modemstat &= ~ (TIOCM_DTR | TIOCM_RTS);
	if (dtr)
		modemstat |= TIOCM_DTR;
	if (rts)
		modemstat |= TIOCM_RTS;
	ioctl(comfid, TIOCMSET, &modemstat);

	return modemstatold;
}

cell
get_modem_control(cell comfid)
{
	int modemstat;

	ioctl(comfid, TIOCMGET, &modemstat);

	return modemstat;
}

cell
open_file(cell stradr)		// Open file
{
	char *name = (char *)stradr;
	int fid;

	fid = open(name, O_RDWR, 0);
	return (cell)fid;
}

void
close_handle(cell fid)
{
	close((int)fid);
}

int
write_file(cell handle, cell len, cell buffer)
{
	size_t actual;
	actual = write((int)handle, (void *)buffer, (size_t)len);
	return actual;
}

int
read_file(cell handle, cell len, cell buffer)
{
	int actual;
	actual = read((int)handle, (void *)buffer, (size_t)len);
	return actual;
}

int
timed_read_com(cell handle, cell ms, cell len, cell buffer)
{
	int actual;

	struct pollfd pollfd;

#ifdef BUFFERED_READ
	if (nbuf) {
		actual = len > nbuf ? nbuf : len;
		memcpy((char *)buffer, bufp, actual);
		nbuf -= actual;
		bufp += actual;
		return actual;
	}
#endif

	pollfd.fd = handle;
	pollfd.events = POLLIN;
	pollfd.revents = 0;

	actual = poll(&pollfd, 1, ms);
#ifdef BUFFERED_READ
	if (actual > 0) {
		nbuf = read((int)handle, (void *)buf, 100);
		bufp = buf;
		if (nbuf < 0)
			nbuf = 0;
	}

	if (nbuf) {
		actual = len > nbuf ? nbuf : len;
		memcpy((char *)buffer, bufp, actual);
		nbuf -= actual;
		bufp += actual;
		return actual;
	}

	return actual;
#else
	if (actual > 0) {
		actual = read((int)handle, (void *)buffer, (size_t)len);
	}
#endif
        return actual;
}

cell
ms(cell nms)
{
    usleep(nms*1000);  // nanosleep(timespec) would be better
}

cell ((* const ccalls[])()) = {
	(cell (*)())open_com,			// Entry # 0
	(cell (*)())close_handle,		// Entry # 1
	(cell (*)())write_file,			// Entry # 2
	(cell (*)())read_file,			// Entry # 3
	(cell (*)())open_file,			// Entry # 4
        (cell (*)())timed_read_com,		// Entry # 5
        (cell (*)())ms,				// Entry # 6
        (cell (*)())set_modem_control,		// Entry # 7
        (cell (*)())get_modem_control,		// Entry # 8
        (cell (*)())set_com_parity,		// Entry # 9
    // Add your own routines here
};

// Forth words to call the above routines may be created by:
//
//  system also
//  0 ccall: sum      { i.a i.b -- i.sum }
//  1 ccall: byterev  { s.in -- s.out }
//
// and could be used as follows:
//
//  5 6 sum .
//  p" hello"  byterev  count type
