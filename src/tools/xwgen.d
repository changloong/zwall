module xwgen ;

import
	tango.sys.Common,
	tango.sys.Process,
	tango.sys.Environment,
	tango.sys.consts.unistd,
	
	tango.stdc.posix.sys.stat,
	tango.stdc.posix.config,
	tango.stdc.posix.sys.types,
	tango.stdc.stddef,
	tango.stdc.stringz,
	
	tango.core.Thread,
	tango.text.Arguments,
	Txt	= tango.text.Util,
	_P	= tango.io.Path ,
	_A	= tango.core.Array,

	tango.io.stream.Lines,
	tango.io.device.File,
	tango.io.device.Array,
	tango.io.FileScan,
	tango.io.FilePath,
	tango.io.Stdout;

extern (C) {
	void exit(int);
	int symlink(char*, char*);
	int chown(char*, uid_t, gid_t);
	int chmod(char*, int);
	int mkdir(char*, int);
	int readlink(char*, char*, int);
	int unlink(char*);
	void* memcpy(void*, void*, size_t);
	int strcmp(char* , char*);
}

struct FNode {
	const Max	= 128 ;
	private{
		ubyte[Max]	tmp ;
		int		len ;
		stat_t	st ;
	}
	
	int mode(){
		return st.st_mode & ~S_IFMT;
	}
	int type(){
		return st.st_mode & S_IFMT;
	}
	
	bool isLink(){
		return type is S_IFLNK;
	}
	
	bool isDir( ) {
		return type is S_IFDIR;
	}
	
	bool isSock(){
		return type is S_IFSOCK ;
	}
	
	bool isExe() {
		int v = mode & 0111 ;
		return v !is 0 ;
	}
	
	char[] Name(){
		return cast(char[]) tmp[0..len] ;
	}
	
	char* Namez(){
		return cast(char*) &tmp[0] ;
	}
	
	char[] readLink() {
		if( !isLink ){
			return Name ;
		}
		char[Max] _tmp;
		int i	= readlink( cast(char*) &tmp[0] , _tmp.ptr, _tmp.length) ;
		if(  i < 1 ){
			Stdout(":readlink `")( Name )("` ")( SysError.lastMsg )(".\n").flush ;
			exit(1);
		}
		assert( i < _tmp.length );
		return _tmp[0..i].dup ;
	}

	bool copyTo(char[] to){
		if( isDir ){
			return false ;
		}
		if( isLink ) {
			auto p = FNode.Open( readLink ) ;
			return p.copyTo( to ) ;
		}
		if( !_P.exists( to ) ){
			_P.copy( Name , to);
		}
		chmod( toStringz(to) , mode );
		return true ;
	}
	
	static FNode* Open(char[] _file, FNode* p = null){
		if(  _file.length  >= Max ){
			Stdout("file name is too long `")(_file)("` ")(".\n").flush ;
			exit(1);
		}
		FNode _p ;
		memcpy( &_p.tmp[0] , &_file[0], _file.length );
		_p.tmp[ _file.length .. $ ] = 0 ;
		_p.len	= _file.length ;
		auto re	= lstat( cast(char*) &_p.tmp[0] , &_p.st ) ;
		if( re !is 0 ){
			int code = SysError.lastCode ;
			if( code !is 2 ){
				Stdout(":lstat `")(_file)("` ")( SysError.lookup(code) )(".\n").flush ;
			}
			return null ;
		}
		if( p is null ){
			p	= new FNode ;
		}
		memcpy( p , &_p, FNode.sizeof );
		return p ;
	}

}

struct _G {
	static char[] to	= "msd/" ;
	static char[] self	= "" ;
	static char[] home	= "" ;
	static char[][]
			ini_files	= [];

	static void Init( char[][] args){
		home 	= _P.standard(Environment.get("HOME")).dup  ;	
		if( args.length > 2 && args[1][0] == '-' ){
			switch(args[1][1..$]){
				case "x":
					gen_ini( args[2..$] );
					break;

			}
			exit(0) ;
		}
		int i	= _A.rfind(args[0] , '/' );
		if( i < args[0].length ){
			self	=  args[0][i+1..$].dup ;
		}else{
			self	= args[0].dup ;
		}
		char[] _ini	= home ~ "/bin/" ~ self ~ ".ini";
		if( !_P.exists( _ini ) ){
			Stdout("default ini file `")(_ini)(" is not exist.\n").flush;
			exit(1);
		}
		ini_files	~= _ini.dup ;

		for(int _i = 1; _i < args.length ; _i++){
			char[] arg	= args[_i];
			auto p	= new FilePath(arg);
			if( p.ext != "ini" ){
				p	= new FilePath( arg ~ ".ini" );
			}
			if( !p.exists ){
				Stdout(" ini file `")( p.toString )(" is not exist.\n").flush;
				exit(1);
			} 
			ini_files	~= p.toString.dup ;
		}
	}

	static void gen_ini(char[][] dirs){
		FNode tmp;
		auto bu	= new Array(1024, 1024);
		foreach( dir; dirs  ){
			if( dir[0] == '/' ) dir	= dir[1..$];
			if( dir.length < 1 ) continue ;
			if( dir[$-1] == '/' ) dir	= dir[0..$-1];
			if( dir.length < 1 ) continue ;
			bu("[/")(dir)("]\n");
			auto fs = new FileScan();
			fs( dir );
			int i = dir.length + 1 ;
			foreach( _file ; fs.files ){
				auto p		= FNode.Open(_file.toString, &tmp);
				if( p.isLink ){
					bu("@")( p.Name[i..$] )("->")( p.readLink )("\n");
				}else{
					bu(p.Name[i..$] )("\n");
				}
			}
			bu("\n");
		}
		Stdout( cast(char[]) bu.slice).flush;
	}
}


struct BSDLite {
	static void create(){
		if( !_P.exists( _G.to ) ){
                        _P.createFolder( _G.to );
                }

		foreach( ini ; _G.ini_files ){
			stdout("-> ")( ini )( "\n").flush;
			_create(ini);
		}
	}
	private static void _create( char[] ini_file ){
		char[] parent	= "" ;
		foreach( _line ;  new Lines!(char)( new File( ini_file , File.ReadExisting) )  ){
			int i	= _A.find(_line, ';' ) ;
			char[] line = Txt.trim(_line[ 0 .. i ] ) ;
			if( line.length < 1 ) 
				continue ;
			if( line.length > 2 ){
				if( line[0] == '['  && line[$-1] == ']' ){
					line	= Txt.trim(line[1..$-1]);
					if( line.length > 1 && line[0] == '/' ){
						parent	= line[1..$] .dup ;
						if( parent[$-1] != '/' ) parent ~= '/' ;
						addDir( parent );
					}
					continue ;
				}else if( line[0] == '"' && line[$-1] == '"' ){
					line      = Txt.trim( line[1..$-1] ) ;
				}
			}
			if( line.length < 1 ) 
				continue ;
			if(  line.length> 3 && line[0] == '@' ){
				auto link	= Txt.split(line[1..$], "->");
				if( link.length == 2 ){
					char[] link_from	= link[0] ;
					char[] link_to	= link[1] ;
					if( link_from[0] == '/' ){
						link_from	= link_from[1..$] ;
					}else{
						link_from	= parent ~ link_from ; 
					}
					symlink( toStringz( link_to ), toStringz( _G.to ~ link_from ) );
				}
				continue ;
			}
			auto files	= Txt.split(line, ":");
			char[] _file	= ( parent ~ files[0] ) .dup  ;
			foreach( c ; files[0] ) if( c is '/' ) {
				addDir( _file );
				break ;
			}
			if( !Copy( "/" ~ _file, _G.to ~ _file ) ){
				continue ;
			}
			if( files.length > 1 ) foreach( file ; files[1..$] ){
				file	= Txt.trim(file);
				if( file.length < 1 )
					continue ;
				if( file[0] == '/' && file.length > 1 ){
			 		addDir(file[1..$]);
					Link( file[1..$],  _file );
				}else{
					foreach( c ; file ) if( c is '/' ) {
						addDir( parent ~ file );
						break ;
					}
					Link( parent ~ file ,  _file );
				}
			}
			Stdout("\t\t")( _file )("\n").flush;
		}
	}
	
	static void addDir(char[] dir){
		FNode t1, t2 ;
		foreach(int i, ref c; dir ){
			if( c == '/' ){
				FNode* from = FNode.Open( "/" ~ dir[0..i] , &t1 );
				if( from is null ){
					continue ;
				}
				scope to   = ( _G.to ~ dir[0..i]).dup ;
				if( !_P.exists( to ) ){
					Stdout("\t")( to  )("\n").flush;
					mkdir( toStringz(to) , from.mode );
                                }
			}
		}
	}

	static bool Copy(char[] from, char[] to){
		auto p	= FNode.Open(from) ;
		if( p is null ) return false;
		return p.copyTo( to ) ;
	}
	
	static void Link(char[] from, char[] to){
		char[] rel	= relPath(from, to );
		auto ret	= symlink( toStringz(rel), toStringz( _G.to ~ from ) );
		Stdout("\t\t")( from )(" \t\t -> \t ")  ( rel ) ("\n") .flush ;
	}
	
	static char[] relPath(char[] from, char[] to){
		char[] rel = null ;
		auto from_	= Txt.split(from, "/" );
		auto to_	= Txt.split(to, "/" );
		int _i  = 0 ;
		for(int i = 0 ; i < from_.length  ; i++ ){
			if( to_.length > i &&  to_[i] != from_[i] ){
				_i	= i ;
				break;
			}
		}
		from_	= from_[_i .. $];
		to_	= to_[_i..$];
		char[][] rel_;
		for( int i = 1; i < from_.length; i++) rel_ ~= ".."; 
		for( int i = 0; i < to_.length; i++) rel_ ~= to_[i]; 
		rel	= Txt.join(rel_, "/");
		return rel.dup ; 
	}
}

struct BSDLib{
	static const char[][]	dirs	= ["bin", "sbin", "usr/bin", "usr/sbin" ];

	static void copy(){
		Environment.cwd( _G.to );
		FNode _fn ;
		auto bu	= new Array(1024, 1024);
		bu("ldd ");
		foreach( dir ; dirs ){
			auto fs	= new FileScan();
			fs(dir);
			foreach( _file ; fs.files ){
				FNode* f = FNode.Open( _file.toString, &_fn );
				if( !f.isLink && f.isExe ){
					bu(" ")(f.Name);
				}
			}
		}
		char[] cmd =  ( cast(char[]) bu.slice ) ;
		bu.clear;
		auto p = new Process (cmd , null ) ;
                p.execute;
                bu.copy( p.stdout ) ;
                char[][] libs    = [] ;
                scope ls        = new Lines!(char)(bu);
                foreach( line; ls ){
                        auto l1 = Txt.split( line, "=>" );
                        if( l1.length is 2 ){
                                auto l2 = Txt.split( l1[1] , "(" );
                                if( l2.length > 1 ){
                                        auto _lib  = Txt.trim( l2[0]  ) ;
                                        char* libz = &_lib[0] ;
                                        char[] lib = libz[ 0 .. _lib.length + 1];
                                        lib[$-1]   = 0 ;
                                        if( _A.contains(libs, lib ) ){
                                                continue ;
                                        }
                                        libs    ~= lib ;
                                }
                        }
                }
		Environment.cwd(`..`);
		Stdout("-> libs\n");
		_A.sort(libs, &sort1);
		foreach( lib ; libs ){
			BSDLite.addDir( lib[1..$] );
			BSDLite.Copy(lib , _G.to ~ lib[1..$] );
			Stdout("\t\t")(lib)("\n");
		}
		Stdout.flush;
	}

	static bool sort1(char[] a, char[] b){
		return strcmp(a.ptr, b.ptr) < 0;
	}

}

void main(char[][] args) {
	_G.Init( args );
	BSDLite.create;
	BSDLib.copy;
}
