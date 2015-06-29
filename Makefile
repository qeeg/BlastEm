ifndef OS
OS:=$(shell uname -s)
endif

ifeq ($(OS),Windows)

MEM:=mem_win.o
BLASTEM:=blastem.exe
CC:=wine gcc.exe
CFLAGS:=-O2 -std=gnu99 -Wreturn-type -Werror=return-type -Werror=implicit-function-declaration -I"C:/MinGW/usr/include/SDL2" -DGLEW_STATIC
LDFLAGS:= -L"C:/MinGW/usr/lib" -lm -lmingw32 -lSDL2main -lSDL2 -lopengl32 -lglu32 -mwindows
CPU:=i686

else

MEM:=mem.o
BLASTEM:=blastem

ifeq ($(OS),Darwin)
LIBS=sdl2 glew
else
LIBS=sdl2 glew gl
endif #Darwin

CFLAGS:=-std=gnu99 -Wreturn-type -Werror=return-type -Werror=implicit-function-declaration -Wno-unused-value -Wno-logical-op-parentheses
FIXUP:=
ifdef PORTABLE
CFLAGS+= -DGLEW_STATIC -Iglew/include
LDFLAGS:=-lm glew/lib/libGLEW.a

ifeq ($(OS),Darwin)
CFLAGS+= -IFrameworks/SDL2.framework/Headers
LDFLAGS+= -FFrameworks -framework SDL2 -framework OpenGL
FIXUP:=install_name_tool -change @rpath/SDL2.framework/Versions/A/SDL2 @executable_path/Frameworks/SDL2.framework/Versions/A/SDL2 ./blastem
endif #Darwin

else
CFLAGS:=$(shell pkg-config --cflags-only-I $(LIBS)) $(CFLAGS)
LDFLAGS:=-lm $(shell pkg-config --libs $(LIBS))

ifeq ($(OS),Darwin)
LDFLAGS+= -framework OpenGL
endif

endif #PORTABLE

ifdef DEBUG
CFLAGS:=-ggdb $(CFLAGS)
LDFLAGS:=-ggdb $(LDFLAGS)
else
CFLAGS:=-O2 -flto $(CFLAGS)
LDFLAGS:=-O2 -flto $(LDFLAGS)
endif #DEBUG
endif #Windows

ifdef Z80_LOG_ADDRESS
CFLAGS+= -DZ80_LOG_ADDRESS
endif

ifdef PROFILE
CFLAGS+= -pg
LDFLAGS+= -pg
endif
ifdef NOGL
CFLAGS+= -DDISABLE_OPENGL
endif

ifdef M68030
CFLAGS+= -DM68030
endif
ifdef M68020
CFLAGS+= -DM68020
endif
ifdef M68010
CFLAGS+= -DM68010
endif

ifndef CPU
CPU:=$(shell uname -m)
endif

TRANSOBJS=gen.o backend.o $(MEM)
M68KOBJS=68kinst.o m68k_core.o
ifeq ($(CPU),x86_64)
M68KOBJS+= m68k_core_x86.o
TRANSOBJS+= gen_x86.o backend_x86.o
else
ifeq ($(CPU),i686)
M68KOBJS+= m68k_core_x86.o
TRANSOBJS+= gen_x86.o backend_x86.o
endif
endif

Z80OBJS=z80inst.o z80_to_x86.o
AUDIOOBJS=ym2612.o psg.o wave.o
CONFIGOBJS=config.o tern.o util.o

MAINOBJS=blastem.o debug.o gdb_remote.o vdp.o render_sdl.o io.o $(CONFIGOBJS) gst.o $(M68KOBJS) $(TRANSOBJS) $(AUDIOOBJS)

ifeq ($(CPU),x86_64)
CFLAGS+=-DX86_64 -m64
LDFLAGS+=-m64
else
ifeq ($(CPU),i686)
CFLAGS+=-DX86_32 -m32
LDFLAGS+=-m32
endif
endif

ifdef NOZ80
CFLAGS+=-DNO_Z80
else
MAINOBJS+= $(Z80OBJS)
endif

ifeq ($(OS),Windows)
MAINOBJS+= glew32s.lib
endif

all : dis zdis stateview vgmplay blastem

$(BLASTEM) : $(MAINOBJS)
	$(CC) -o $(BLASTEM) $(MAINOBJS) $(LDFLAGS)
	$(FIXUP)

dis : dis.o 68kinst.o tern.o vos_program_module.o
	$(CC) -o dis dis.o 68kinst.o tern.o vos_program_module.o

zdis : zdis.o z80inst.o
	$(CC) -o zdis zdis.o z80inst.o

libemu68k.a : $(M68KOBJS) $(TRANSOBJS)
	ar rcs libemu68k.a $(M68KOBJS) $(TRANSOBJS)

trans : trans.o $(M68KOBJS) $(TRANSOBJS)
	$(CC) -o trans trans.o $(M68KOBJS) $(TRANSOBJS)

transz80 : transz80.o $(Z80OBJS) $(TRANSOBJS)
	$(CC) -o transz80 transz80.o $(Z80OBJS) $(TRANSOBJS)

ztestrun : ztestrun.o $(Z80OBJS) $(TRANSOBJS)
	$(CC) -o ztestrun ztestrun.o $(Z80OBJS) $(TRANSOBJS)

ztestgen : ztestgen.o z80inst.o
	$(CC) -ggdb -o ztestgen ztestgen.o z80inst.o

stateview : stateview.o vdp.o render_sdl.o $(CONFIGOBJS) gst.o
	$(CC) -o stateview stateview.o vdp.o render_sdl.o $(CONFIGOBJS) gst.o $(LDFLAGS)

vgmplay : vgmplay.o render_sdl.o $(CONFIGOBJS) $(AUDIOOBJS)
	$(CC) -o vgmplay vgmplay.o render_sdl.o $(CONFIGOBJS) $(AUDIOOBJS) $(LDFLAGS)
	
test : test.o vdp.o
	$(CC) -o test test.o vdp.o

testgst : testgst.o gst.o
	$(CC) -o testgst testgst.o gst.o

test_x86 : test_x86.o gen_x86.o gen.o
	$(CC) -o test_x86 test_x86.o gen_x86.o gen.o

test_arm : test_arm.o gen_arm.o mem.o gen.o
	$(CC) -o test_arm test_arm.o gen_arm.o mem.o gen.o

gen_fib : gen_fib.o gen_x86.o mem.o
	$(CC) -o gen_fib gen_fib.o gen_x86.o mem.o

offsets : offsets.c z80_to_x86.h m68k_core.h
	$(CC) -o offsets offsets.c

vos_prog_info : vos_prog_info.o vos_program_module.o
	$(CC) -o vos_prog_info vos_prog_info.o vos_program_module.o

%.o : %.S
	$(CC) -c -o $@ $<

%.o : %.c
	$(CC) $(CFLAGS) -c -o $@ $<

%.bin : %.s68
	vasmm68k_mot -Fbin -m68000 -no-opt -spaces -o $@ -L $@.list $<

%.bin : %.sz8
	vasmz80_mot -Fbin -spaces -o $@ $<

clean :
	rm -rf dis trans stateview test_x86 gen_fib *.o
