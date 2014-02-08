#!/usr/bin/env - SHELL=/bin/sh TERM=xterm-256color COMMAND_MODE=unix2003 LC_ALL=C LANG=C /bin/ksh
set -e
set -o pipefail
set -u
set -x

define(){ eval ${1}='"${*:2}"'; }

define CAT                  /bin/cat
define CHMOD                /bin/chmod
define CUT                  /usr/bin/cut
define FIND                 /usr/bin/find
define GETCONF              /usr/bin/getconf
define GREP                 /usr/bin/grep
define INSTALL_NAME_TOOL    /usr/bin/install_name_tool
define LN                   /bin/ln
define MKDIR                /bin/mkdir -p
define OTOOL                /usr/bin/otool
define PATCH                /usr/bin/patch
define RM                   /bin/rm
define RSYNC                /usr/bin/rsync -a
define SED                  /usr/bin/sed
define SW_VERS              /usr/bin/sw_vers
define UNAME                /usr/bin/uname
define XCODEBUILD           /usr/bin/xcodebuild

define PROJECTROOT      $(cd "$(dirname "$0")" && pwd)
define SRCROOT          ${PROJECTROOT}/src

define TMPDIR        /tmp/_build

define INSTALL_PREFIX   /usr/local/wine
define W_PREFIX         ${INSTALL_PREFIX}
define W_BINDIR         ${W_PREFIX}/bin
define W_INCDIR         ${W_PREFIX}/include
define W_LIBDIR         ${W_PREFIX}/lib
define W_DATADIR        ${W_PREFIX}/share
define PREFIX           /tmp/local
define BINDIR           ${PREFIX}/bin
define INCDIR           ${PREFIX}/include
define LIBDIR           ${W_PREFIX}/lib
define DATADIR          ${PREFIX}/share

define MACPORTSDIR      /opt/local
define XDIR             /opt/X11
define XINCDIR          ${XDIR}/include
define XLIBDIR          ${XDIR}/lib

CS_PATH=$(${GETCONF} PATH)

PATH=\
${BINDIR}:\
${MACPORTSDIR}/libexec/ccache:\
${MACPORTSDIR}/libexec/git-core:\
${MACPORTSDIR}/libexec/gnubin:\
${CS_PATH}
export PATH

AC_PATH=\
${MACPORTSDIR}/libexec/gnubin:\
${MACPORTSDIR}/bin:\
${MACPORTSDIR}/sbin:\
${CS_PATH}

DARWIN_VERSION=$(
    ${UNAME} -r
)
MACOSX_DEPLOYMENT_TARGET=$(
    ${SW_VERS} -productVersion \
    | ${CUT} -d. -f-2
)
export MACOSX_DEPLOYMENT_TARGET
SDKROOT=$(
    ${XCODEBUILD} -version -sdk macosx${MACOSX_DEPLOYMENT_TARGET} \
    | ${SED} -n "/^Path: /s///p"
)
TRIPLE=i686-apple-darwin${DARWIN_VERSION}

set -a
define CC                   gcc-apple-4.2
define CXX                  g++-apple-4.2
define CFLAGS               -m32 -arch i386 -O3 -mtune=generic
define CPPFLAGS             -isysroot ${SDKROOT} -I${INCDIR}
define CXXFLAGS             ${CFLAGS}
define CXXCPPFLAGS          ${CPPFLAGS}
define LDFLAGS              -Wl,-headerpad_max_install_names -Wl,-syslibroot,${SDKROOT} -arch i386 -Z -L${LIBDIR} -L/usr/lib -F/System/Library/Frameworks

define CCACHE_PATH          ${MACPORTSDIR}/bin

define FONTFORGE            ${MACPORTSDIR}/bin/fontforge
define MAKE                 ${MACPORTSDIR}/bin/gmake
define MSGFMT               ${MACPORTSDIR}/bin/msgfmt
define NASM                 ${MACPORTSDIR}/bin/nasm
define PKG_CONFIG           ${MACPORTSDIR}/bin/pkg-config
define PKG_CONFIG_LIBDIR    ${LIBDIR}/pkgconfig:/usr/lib/pkgconfig
set +a

#-------------------------------------------------------------------------------

autogen()
{
    PATH=${AC_PATH} NOCONFIGURE=1 ./autogen.sh ${@-}
}
autoreconf()
{
    PATH=${AC_PATH} NOCONFIGURE=1 command autoreconf -i ${@-}
}
configure()
{
    ./configure --prefix=${PREFIX} --build=${TRIPLE} --libdir=${LIBDIR} ${@-}
}
git_checkout()
{
    git checkout -f ${1-master}
}
make_install()
{
    ${MAKE} --jobs=3
    ${MAKE} install
}
clone_repos()
{
    ${RSYNC} --delete ${SRCROOT}/${1}/ ${TMPDIR}/${1}
    cd ${TMPDIR}/${1}
}

#-------------------------------------------------------------------------------

build_freetype()
{
    typeset name
    name=freetype

    clone_repos ${name}
    git_checkout
    autogen
    configure --disable-static
    make_install
}

build_xz()
{
    typeset name
    name=xz

    clone_repos ${name}
    git_checkout v5.0
    autogen
    configure \
        --disable-dependency-tracking \
        --disable-nls \
        --disable-static
    make_install
}

build_jpeg()
{
    typeset name
    name=libjpeg-turbo

    clone_repos ${name}
    git_checkout
    ${SED} -i "" "s|\$(datadir)/doc|&/libjpeg-turbo|" Makefile.am
    autoreconf
    configure \
        --disable-dependency-tracking \
        --disable-static \
        --with-jpeg8
    make_install
}

build_tiff()
{
    typeset name
    name=libtiff

    clone_repos ${name}
    git_checkout branch-3-9
    configure \
        --disable-dependency-tracking \
        --disable-cxx \
        --disable-jbig \
        --disable-static \
        --with-apple-opengl-framework \
        --with-x \
        --x-inc=${XINCDIR} \
        --x-lib=${XLIBDIR}
    make_install
}

build_lcms()
{
    typeset name
    name=Little-CMS

    clone_repos ${name}
    git_checkout
    configure \
        --disable-dependency-tracking \
        --disable-static
    make_install
}

build_png()
{
    typeset name
    name=libpng

    clone_repos ${name}
    git_checkout libpng16
    autogen
    configure \
        --disable-dependency-tracking \
        --disable-static
    make_install
}

build_wine()
{
    typeset name
    name=wine

    typeset configure_args
    configure_args=(
        --disable-win16
        --without-capi
        --without-gphoto
        --without-gsm
        --without-oss
        --without-sane
        --without-v4l
        --with-x
        --x-inc=${XINCDIR}
        --x-lib=${XLIBDIR}
    )

    clone_repos ${name}
    git_checkout
    patch_wine
    ./configure \
        --prefix=${W_PREFIX} \
        --build=${TRIPLE} \
        "${configure_args[@]}"
    make_install
}

#-------------------------------------------------------------------------------

patch_wine()
{
    ${PATCH} -Np1 <<\!
diff --git a/loader/main.c b/loader/main.c
index ac67290..0926f08 100644
--- a/loader/main.c
+++ b/loader/main.c
@@ -87,6 +87,8 @@ static inline void reserve_area( void *addr, size_t size )
 static void check_command_line( int argc, char *argv[] )
 {
     static const char usage[] =
+        "Darwin Kernel Version 10.8.0: Tue Jun  7 16:33:36 PDT 2011; root:xnu-1504.15.3~1/RELEASE_I386\n"
+        "\n"
         "Usage: wine PROGRAM [ARGUMENTS...]   Run the specified program\n"
         "       wine --help                   Display this help and exit\n"
         "       wine --version                Output version information and exit";



diff --git a/include/wine/wine_common_ver.rc b/include/wine/wine_common_ver.rc
index 77ca4a8..589cf22 100644
--- a/include/wine/wine_common_ver.rc
+++ b/include/wine/wine_common_ver.rc
@@ -100,7 +100,7 @@ FILESUBTYPE    WINE_FILESUBTYPE
 {
     BLOCK "StringFileInfo"
     {
-	BLOCK "040904E4" /* LANG_ENGLISH/SUBLANG_DEFAULT, CP 1252 */
+	BLOCK "041104E4" /* LANG_JAPANESE/SUBLANG_DEFAULT, CP 1252 */
 	{
 	    VALUE "CompanyName", "Microsoft Corporation"  /* GameGuard depends on this */
 	    VALUE "FileDescription", WINE_FILEDESCRIPTION_STR
@@ -115,6 +115,6 @@ FILESUBTYPE    WINE_FILESUBTYPE
     }
     BLOCK "VarFileInfo"
     {
-	VALUE "Translation", 0x0409, 0x04E4 /* LANG_ENGLISH/SUBLANG_DEFAULT, CP 1252 */
+	VALUE "Translation", 0x0411, 0x04E4 /* LANG_JAPANESE/SUBLANG_DEFAULT, CP 1252 */
     }
 }



diff --git a/programs/iexplore/main.c b/programs/iexplore/main.c
index 73fec25..c678272 100644
--- a/programs/iexplore/main.c
+++ b/programs/iexplore/main.c
@@ -40,7 +40,7 @@ static BOOL check_native_ie(void)
     static const WCHAR wineW[] = {'W','i','n','e',0};
     static const WCHAR file_desc_strW[] =
         {'\\','S','t','r','i','n','g','F','i','l','e','I','n','f','o',
-         '\\','0','4','0','9','0','4','e','4',
+         '\\','0','4','1','1','0','4','e','4',
          '\\','F','i','l','e','D','e','s','c','r','i','p','t','i','o','n',0};
 
     size = GetFileVersionInfoSizeW(browseui_dllW, &handle);



diff --git a/dlls/winemac.drv/cocoa_window.m b/dlls/winemac.drv/cocoa_window.m
index 48c5056..c949518 100644
--- a/dlls/winemac.drv/cocoa_window.m
+++ b/dlls/winemac.drv/cocoa_window.m
@@ -781,6 +781,9 @@ - (BOOL) orderBelow:(WineWindow*)prev orAbove:(WineWindow*)next activate:(BOOL)a
 
             [controller transformProcessToForeground];
 
+            [NSApp setPresentationOptions:NSApplicationPresentationAutoHideDock|
+                                          NSApplicationPresentationAutoHideMenuBar];
+
             if (activate)
                 [NSApp activateIgnoringOtherApps:YES];
 



diff --git a/fonts/Makefile.in b/fonts/Makefile.in
index 43ad860..bdf97a5 100644
--- a/fonts/Makefile.in
+++ b/fonts/Makefile.in
@@ -53,11 +53,7 @@ BITMAP_FONTS  = \
 	vgas874.fon
 
 TRUETYPE_FONTS = \
-	marlett.ttf \
-	symbol.ttf \
-	tahoma.ttf \
-	tahomabd.ttf \
-	wingding.ttf
+	marlett.ttf
 
 all: $(BITMAP_FONTS)
 



diff --git a/loader/Makefile.in b/loader/Makefile.in
index 37104a7..d6c07e0 100644
--- a/loader/Makefile.in
+++ b/loader/Makefile.in
@@ -13,10 +13,7 @@ PROGRAMS = \
 	wine64-preloader
 
 MANPAGES = \
-	wine.de.UTF-8.man.in \
-	wine.fr.UTF-8.man.in \
-	wine.man.in \
-	wine.pl.UTF-8.man.in
+	wine.man.in
 
 IN_SRCS = \
 	wine.inf.in \



diff --git a/server/Makefile.in b/server/Makefile.in
index 9711cac..96a1b1c 100644
--- a/server/Makefile.in
+++ b/server/Makefile.in
@@ -48,8 +48,6 @@ C_SRCS = \
 PROGRAMS = wineserver wineserver-installed
 
 MANPAGES = \
-	wineserver.de.UTF-8.man.in \
-	wineserver.fr.UTF-8.man.in \
 	wineserver.man.in
 
 INSTALLDIRS = $(DESTDIR)$(bindir)



diff --git a/tools/Makefile.in b/tools/Makefile.in
index 3ee8473..19d2f6c 100644
--- a/tools/Makefile.in
+++ b/tools/Makefile.in
@@ -8,8 +8,6 @@ PROGRAMS = \
 	sfnt2fnt$(EXEEXT)
 
 MANPAGES = \
-	winemaker.de.UTF-8.man.in \
-	winemaker.fr.UTF-8.man.in \
 	winemaker.man.in
 
 C_SRCS = \
@@ -41,8 +39,6 @@ sfnt2fnt$(EXEEXT): sfnt2fnt.o
 .PHONY: install install-lib install-dev uninstall
 
 install install-lib::
-	$(INSTALL_DATA) $(srcdir)/wine.desktop $(DESTDIR)$(datadir)/applications/wine.desktop
-	-$(UPDATE_DESKTOP_DATABASE)
 
 install install-dev:: install-man-pages
 	$(INSTALL_SCRIPT) $(srcdir)/winemaker $(DESTDIR)$(bindir)/winemaker



diff --git a/programs/explorer/explorer.c b/programs/explorer/explorer.c
index 1b900d0..23a4a84 100644
--- a/programs/explorer/explorer.c
+++ b/programs/explorer/explorer.c
@@ -44,8 +44,8 @@ WINE_DEFAULT_DEBUG_CHANNEL(explorer);
 #define NAV_TOOLBAR_HEIGHT 30
 #define PATHBOX_HEIGHT 24
 
-#define DEFAULT_WIDTH 640
-#define DEFAULT_HEIGHT 480
+#define DEFAULT_WIDTH 800
+#define DEFAULT_HEIGHT 600
 
 
 static const WCHAR EXPLORER_CLASS[] = {'W','I','N','E','_','E','X','P','L','O','R','E','R','\0'};



diff --git a/dlls/winemac.drv/keyboard.c b/dlls/winemac.drv/keyboard.c
index a46d324..66cc4f2 100644
--- a/dlls/winemac.drv/keyboard.c
+++ b/dlls/winemac.drv/keyboard.c
@@ -238,14 +238,14 @@ static const struct {
     { VK_BACK,                  0x0E,           TRUE },     /* kVK_Delete */
     { 0,                        0,              FALSE },    /* 0x34 unused */
     { VK_ESCAPE,                0x01,           TRUE },     /* kVK_Escape */
-    { VK_RMENU,                 0x38 | 0x100,   TRUE },     /* kVK_RightCommand */
-    { VK_LMENU,                 0x38,           TRUE },     /* kVK_Command */
+    { 0,                        0,              FALSE },    /* kVK_RightCommand */
+    { 0,                        0,              FALSE },    /* kVK_Command */
     { VK_LSHIFT,                0x2A,           TRUE },     /* kVK_Shift */
     { VK_CAPITAL,               0x3A,           TRUE },     /* kVK_CapsLock */
-    { 0,                        0,              FALSE },    /* kVK_Option */
+    { VK_LMENU,                 0x38,           TRUE },     /* kVK_Option */
     { VK_LCONTROL,              0x1D,           TRUE },     /* kVK_Control */
     { VK_RSHIFT,                0x36,           TRUE },     /* kVK_RightShift */
-    { 0,                        0,              FALSE },    /* kVK_RightOption */
+    { VK_RMENU,                 0x38 | 0x100,   TRUE },     /* kVK_RightOption */
     { VK_RCONTROL,              0x1D | 0x100,   TRUE },     /* kVK_RightControl */
     { 0,                        0,              FALSE },    /* kVK_Function */
     { VK_F17,                   0x68,           TRUE },     /* kVK_F17 */



diff --git a/dlls/winemac.drv/cocoa_app.m b/dlls/winemac.drv/cocoa_app.m
index d499fd1..d7dec01 100644
--- a/dlls/winemac.drv/cocoa_app.m
+++ b/dlls/winemac.drv/cocoa_app.m
@@ -223,7 +223,6 @@ - (void) transformProcessToForeground
             item = [submenu addItemWithTitle:title action:@selector(hide:) keyEquivalent:@""];
 
             item = [submenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
-            [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
 
             item = [submenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
 
@@ -234,7 +233,6 @@ - (void) transformProcessToForeground
             else
                 title = @"Quit";
             item = [submenu addItemWithTitle:title action:@selector(terminate:) keyEquivalent:@"q"];
-            [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
             item = [[[NSMenuItem alloc] init] autorelease];
             [item setTitle:@"Wine"];
             [item setSubmenu:submenu];
@@ -247,7 +245,6 @@ - (void) transformProcessToForeground
             if ([NSWindow instancesRespondToSelector:@selector(toggleFullScreen:)])
             {
                 item = [submenu addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
-                [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask];
             }
             [submenu addItem:[NSMenuItem separatorItem]];
             [submenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];



!

    $SED "s|@WINE_VERSION@|$(< VERSION)|
          s|@UNAME@|$(uname -v)|
          s|@TRIPLE@|$TRIPLE|
          s|@CONFIGURE_ARGS@|${configure_args[*]}|" <<\! | $PATCH -Np1
diff --git a/loader/main.c b/loader/main.c
index ac67290..7cdafeb 100644
--- a/loader/main.c
+++ b/loader/main.c
@@ -87,6 +87,11 @@ static inline void reserve_area( void *addr, size_t size )
 static void check_command_line( int argc, char *argv[] )
 {
     static const char usage[] =
+        "@WINE_VERSION@  Nihonshu binary edition\n"
+        "  Build: @UNAME@\n"
+        "  Target: @TRIPLE@\n"
+        "  Configured with: @CONFIGURE_ARGS@\n"
+        "\n"
         "Usage: wine PROGRAM [ARGUMENTS...]   Run the specified program\n"
         "       wine --help                   Display this help and exit\n"
         "       wine --version                Output version information and exit";
!

    $SED -i '' "
        /^wine_fn_config_program/s|,installbin||
        /^wine-installed: main.o wine_info.plist/{
            n
            s|\$| -Wl,-rpath,$XLIBDIR -Wl,-rpath,/usr/lib|
        }
    " configure
}

#-------------------------------------------------------------------------------

${RM} -rf   ${INSTALL_PREFIX}
${RM} -rf   ${TMPDIR}

${MKDIR}    ${INSTALL_PREFIX}
${MKDIR}    ${TMPDIR}
${MKDIR}    ${W_BINDIR}
${MKDIR}    ${W_INCDIR}
${MKDIR}    ${W_LIBDIR}
${MKDIR}    ${BINDIR}
${MKDIR}    ${INCDIR}
${MKDIR}    ${LIBDIR}

build_xz
build_png
build_jpeg
build_tiff
build_freetype
build_lcms
build_wine

change_iname()
{
    src=$1

    case ${src} in
    *.dylib)
        set -- $(${OTOOL} -XD ${src})
        case ${1} in
        /*)
            ${INSTALL_NAME_TOOL} -id @rpath/${src##*/} ${src}
            ;;
        esac
        ;;
    esac

    set -- $(${OTOOL} -XL ${1} | ${GREP} -o '.*\.dylib')
    for f
    {
        case ${f} in
        ${LIBDIR}/*)
            ${INSTALL_NAME_TOOL} -change ${f} @rpath/${f##*/} ${src}
            ;;
        esac
    }
}

set -- $(
    ${FIND} ${W_LIBDIR} -type f \( -name "*.dylib" -o -name "*.so" \)
)

#for f
#{
#    change_iname ${f}
#}

LIBDIR=$LIBDIR \
/usr/bin/ruby - "$@" <<\!
ARGV.each {|f|
    %x[/usr/bin/otool -XD #{f}].each_line {|line|
        old = line.split[0]
        next if old.start_with?("@")
        new = File.join("@rpath", File.basename(old))
        cmd = ['/usr/bin/install_name_tool', '-id', new, f]
        if system(*cmd)
            p cmd
        else
            exit(1)
        end
    }

    %x[/usr/bin/otool -XL #{f}].each_line {|line|
        old = line.split[0]
        next unless old.start_with?(ENV["LIBDIR"])
        new = File.join("@rpath", File.basename(old))
        cmd = ['/usr/bin/install_name_tool', '-change', old, new, f]
        if system(*cmd)
            p cmd
        else
            exit(1)
        end
    }
}
!

${RM} -rf ${LIBDIR}/*.la
${RM} -rf ${LIBDIR}/pkgconfig
