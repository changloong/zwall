//: -ofz:\dmd\scite\dmake.exe 

import 
	tango.stdc.stringz ,
	
	Ary	= tango.core.Array ,
	Txt	= tango.text.Util ,
	Int	= tango.text.convert.Integer ,
	Flo	= tango.text.convert.Float ,
	Utf	= tango.text.convert.Utf ,
	Pth	= tango.io.Path ,
	
	tango.sys.Common ,
	tango.sys.Environment ,
	tango.sys.Process ,
	
	tango.time.Clock,
	
	tango.io.FilePath ,
	tango.io.FileScan ,
	tango.io.device.Array ,
	tango.io.device.File ,
	tango.io.stream.Lines ,
	
	tango.io.Stdout;

version (Windows){
	import	tango.sys.win32.UserGdi ;
	extern(Windows) uint GetModuleFileNameW(void*, wchar*, uint);
	
	char[] getThisPath(){
		scope wchar[250]	path;
		GetModuleFileNameW(null, path.ptr, path.length);
		scope file		= Utf.toString(fromString16z(path.ptr)) ;
		return file.dup ;
	}
	
}
extern(C){
	void exit(int);
	int memcpy(void*, void*, size_t);
}

void main(char[][] args){

	Dmake.Init(args[0]) ;
	Dmake.make(args[1..$]);

	Dmake.build ;

}

struct G{
	static const char[][]	All_Exts		= [ "d",  "di", "res", "def", "obj", "lib" ];
	static const char[][]	D_Exts		= ["d", "di"];
	
	static const char[]	conf_file		= r"dmake.conf";
	static const char[]	gui_option	= r"-L/SUBSYSTEM:windows:4";
	static const int	seek_deep	= 5 ;
	
	version( Windows ){
		static const Exe_Ext	= ".exe" ;
		static const Lib_Ext	= ".lib" ;
		static const Dll_Ext	= ".dll" ;
		static const char[][]	Exe_Exts		= ["exe", "com"];
		static const dmd_ini	= "sc.ini" ;
	}else{
		static const Exe_Ext	= "" ;
		static const Lib_Ext	= ".a" ;
		static const Dll_Ext	= ".so" ;
		static const char[][]	Exe_Exts		= [ "" ];
		static const dmd_ini	= "dmd.conf" ;
	}
	
	static const default_dmd	= "dmd" ;
	static const dmd_arg_file	= "@dmake.txt\0" ;
	
	static const
		Dmake_Dir_Tag	= `%DMAKE_DIR%` ,
		Dmd_Dir_Tag		= `%@P%` ;
	static char[] 
		Dmd_Dir_Val ,
		Dmake_Dir_Val ;
}


struct QuoteFruct{
	static QuoteFruct Init(char[] _d, char _tok = ' ' ){
		QuoteFruct q; 
		q.d	= Txt.trim(_d);
		q.tok	= _tok ;
		return q ;
	}
	private char	tok ;
        private char[]	d ;
        int opApply (int delegate (ref char[]) dg){
		int		ret ;
		char[]	token ;
		int		pos ;
		bool		isQuote ;
		char[]	q ;
		bool		isLine	= this.tok == '\n';
		for(int i = 0 ; i < d.length ; i++ ){
			if( isQuote ) {
				if( d[i] == '\\' ){
					for(int j = i +1 ; j < d.length ; j++){
						if( d[j] != '\\' ){
							j	= j - i ;
							i	= i + j + j -1 ;
							break ;
						}
					}
					continue ;
				}
			}
			if( d[i] is '"' ){
				isQuote	= !isQuote ;
			}
			if( !isQuote ){
				
				if( isLine ? ( d[i] is '\n' || d[i] is '\r' ) : ( d[i] is this.tok) ){
					q	= d[pos..i ];
					ret	= dg( q );
					if( ret != 0 ){
						return ret ;
					}
					for( pos	= i + 1  ; pos < d.length ; pos++){
						if( d[pos] != ' ' ){
							i	= pos -1 ;
							break ;
						}
					}
				}
			}
		}
		if( pos < d.length ){
			q	= d[pos..$];
			ret	= dg( q );
		}
                return ret;
        }
}


struct Env {
	static {
		private FilePath	_cwd = null ;
		
		void cwd(char[] path){
			Environment.cwd( path ) ;
			_cwd	= new FilePath( Environment.cwd );
		}
		FilePath cwd(){
			if( _cwd is null ){
				_cwd	= new FilePath( Environment.cwd );
			}
			return _cwd ;
		}
	}
}

struct _Text {
	char[] val ;
	static _Text* Init(char[] val){
		auto p	= new _Text ;
		p.val		= val .dup ;
		return p;
	}
	
	
	static char[] unescape(char[] _val ){
		char[] val	= new char[ _val.length ];
		int j	= 0;
		for(int i = 0 ; i < _val.length ; i++ ){
			if( _val[i] == '\\' ){
				i++;
				if( i < _val.length )
					val[j++]	= _val[i] ;
			}else{
				val[j++]	= _val[i] ;
			}
		}
		return val[ 0 .. j ] ;
	}
	
	static char[] strip(char[] _val ){
		char[] val = Txt.trim(_val) ;
		if( val.length > 1 && val[0] == '"' && val[$-1] == '"' ){
			val	= Txt.trim( unescape(val[1..$-1]) );
		}
		return val ;
	}
	
	static char[][] split(char[] _val, char pat){
		int pos		= 0 ;
		char[][] vals	= [] ;
		void add_val(char[] val){
			if( val is null ){
				return ;
			}
			if( val.length > 1 && val[0] == '"' && val[$-1] == '"' ){
				vals	~= unescape(val[1..$-1]);
			} else if ( val.length > 0 ) {
				vals	~= val.dup ;
			}
		}
		for(int i = 0 ; i < _val.length ; i++ ){
			if( _val[i] == '\\' ){
				for(int j = i +1 ; j < _val.length ; j++){
					if( _val[j] != '\\' ){
						j	= j - i ;
						i	= i + j + j  -1 ;
						break ;
					}
				}
			}else if( _val[i] == pat ){
				add_val( _val[ pos .. i ]  );
				pos	= ++i ; 
			}
		}
		if( pos < _val.length ){
			add_val( _val[ pos .. $ ] );
		}
		return vals ;
	}
	
	static bool startWith(char[] src, char[] obj){
		if( src.length < obj.length ){
			return false ;
		}
		return src[ 0 .. obj.length] == obj ;
	}
}
struct _Flag {
	char[]	_all , _release, _debug = null ;
}
struct _File {
	char[]	_file ;

	char[] toString(){
		return _file ;
	}
	
	static _File* Init(char[] val){
		auto p	= new _File ;
		p._file	= TruePath(val) ;
		return p;
	}
	
	static char* double_dot(char* left, char* right ){
		char* _right, _left , _last = null ;
		int	count ;
		for(; right >= left ; right = _left ){
			
			for( _right = right; _right >= left; _right--){
				if( *_right is '/' ){
					for( _left = _right; _left >=left ; _left--){
						if( *_left !is '/' ){
							break ;
						}
					}
					break;
				}
			}
			if( _left is right ){
				break ;
			}
			int len	= right - _right ;
			
			bool isDots	= true ;
			for(char* i = right; i > _right; i--){
				if(*i !is '.' ){
					isDots	= false ;
					break ;
				}
			}
			if( isDots ){
				if( len > 1 ){
					count++;
				}
				//Stdout.formatln("{}: {}",__LINE__,  (_right+1)[ 0.. len ] ).flush ;
			}else{
				_last	= _left ;
				count-- ;
				//Stdout.formatln("{}: {}",__LINE__,  (_right+1)[ 0.. len ] ).flush ;
			}
			if(count < 0 ) break ;
		}
		if( _last !is null ){
			if( count < 0 ){
				return right ;
			}
			if( _last <= left ){
				return left ;
			}
			version(Windows){
				if( _last - left == 1 && left[1] is ':' ){
					_last++ ;
				}
			}
			return _last ;
		}
		return right ;
	}
	
	static char[] TruePath(char[] _path ){
		if( _path.length is 0 ){
			Stdout("TruePath from empty string ").flush;
			exit(0);
		}
		bool isAbsolute	= false ;
		if( _path[0] is  '/' || _path[0] is  '\\' ){
			isAbsolute	= true ;
		}
		version(Windows){
			if( _path.length > 2 ){
				if( _path[0] >= 'a' && _path[0] <='z' || _path[0] >= 'A' && _path[0] <='Z' ){
					if( _path[1] is ':' && ( _path[2] is '/' || _path[2] is '\\' ) ){
						isAbsolute	= true ;
					}
				}
			}
		}
		char[] path ;
		if( !isAbsolute ){
			char[] cwd	= Env.cwd.toString ;
			path		= new char[ _path.length + cwd.length ];
			memcpy( &path[0], &cwd[0], cwd.length );
			memcpy( &path[cwd.length], &_path[0], _path.length );
		}else{
			path		= _path.dup ;
		}
		for(int i =0 ; i < path.length; i++) if( path[i] is '\\' ) path[i] = '/' ;
		
		int dot_pos	= Ary.find(path, '.' ) ;
		int sep_pos= Ary.rfind(path, '/' ) ;
		int len	= path.length ;
		int pos ;
		if(  dot_pos > sep_pos  ) {
			if( sep_pos < len ){
				for( int i = sep_pos+1; i < len ; i++ ){
					if( path[i] !is '.' ){
						return path ;
					}
				}
				pos	= len  - sep_pos ;
				if( pos is 2 ) return path[0..$-1];
				if( pos is 3 ){
					pos	= Ary.rfind(path[0..sep_pos] , '/' ) ;
					version(Windows){
						if( pos is 2 ) pos = 3 ;
					}
					return path[0..pos] ;
				}
				Stdout("invalid path `")(_path)("` \n").flush;
				exit(0);
			}
			return path ;
		}

		version(Windows){
			char* _start	= &path[2] ;
		}else{
			char* _start	= &path[0] ;
		}
		
		char[] path_	= new char[len+1];
		char* _ptr		= &path_[$-2] ;
		
		for( char* i = &path[$-1]  ;  i > _start ;  ){
			char* p	= double_dot( _start, i );
			
			char* sep	= p ;
			while( sep > _start ){
				if( *sep is '/' ) break;
				sep--;
			}
			
			for(char* _p = p ; _p > _start; _p--){
				if( _p <= sep ) break ;
				*_ptr	= *_p ;
				_ptr--;
			}
			*_ptr	= '/' ;
			_ptr--;
			i	= sep ;
		}
		version(Windows){
			if( &path_[$-3] > _ptr && _ptr[1] is '/' && _ptr[2] is '/'  ){
				_ptr++;
			}
			*_ptr	= ':' ;
			_ptr--;
			*_ptr	= path[0];
			_ptr--;
		}
		path_[$-1]	= 0 ;
		
		return  path_[ _ptr - path_.ptr + 1 ..$-1]  ;
	}
	

	

	static char[] RelPath(char[] base_dir , char[] to){
		char[] rel	= null ;
		auto from_	= Txt.split(base_dir, "/" );
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

final class Args{
	alias Args	This ;
	enum : uint {
		
		kBool  = 0 ,
		kValue ,
		kOf , 
		kDebug ,
		
		vBool		= 0	, 
		vInt 		= 1 << 8 , 
		vText 	= 2 << 8 , 
		vStrings 	= 3 << 8 , 
		vDebug 	= 4 << 8 ,
		vFlag 	= 5 << 8 ,
		vDir 		= 6 << 8 ,
		vFile 		= 7 << 8 ,
		vPath	= 8 << 8 , 
		vDirs		= 9 << 8 ,
		vFiles		= 10 << 8 ,
		vPaths	= 11	<< 8 , 
		vBool2	= 12 << 8	, 
		vLazyDirs 	= 13 << 8 , 
		
		xDmd	 	= 0 ,
		xDmake	= 1 << 16 ,
		
	}
	

	struct Arg {
		char[]	key 	;
		uint		type	;
		union {
			int[]		_number ;
			_File*[]	_file ;
			_Text*[]	_text ;
			
			_Text*[]	strings ;
			_Flag*[]	flags ;
			_File*[]	files ;
		}
		bool function(Arg*, char[]) match = & match_default ;
		
		uint ktype(){
			return type & 0xff ;
		}
		uint vtype(){
			return type & 0xff_00 ;
		}
		uint xtype(){
			return type & 0xff_00_00 ;
		}
		uint isDone(){
			return  type >> 24 ;
		}
		void isDone(uint v){
			type	= ( v << 24 ) | ( type & 0xff_ff_ff );
		}
		
		
		int number(){
			if( _number.length ){
				return _number[0] ;
			}
			return 0 ;
		}
		void number(char[] val){
			if( _number.length is 0 ){
				_number.length 	= 1 ;
			}
			_number[0]	= Int.parse( _Text.strip( val ) ) ;
		}
		
		char[] text(){
			if( _text.length is 0 ){
				return null ;
			}
			return _text[0].val ;
		}
		
		void text(char[] val ){
			if( _text.length is 0 ){
				_text.length 	= 1 ;
			}
			_text[0]	= _Text.Init( _Text.strip(val) )  ;
		}
		
		_File* file(){
			if( _file.length is 0 ){
				return null ;
			}
			return _file[0] ;
		}
		
		void file(char[] val ){
			if( _file.length is 0 ){
				_file.length 	= 1 ;
			}
			_file[0]	= _File.Init( _Text.strip(val) )  ;
		}
		
		private char[] getValue(char[] _val ){	
			char[] val	= Txt.trim( _val ); 
			if( val.length < key.length || val[0..key.length] != key ){
				return null ;
			}
			val	= val[ key.length .. $ ] ; 
			if( ktype is kValue){
				//Stdout.formatln(" `{}` => `{}`", key , val);
			}
			switch( ktype ){
				case kBool :
					if( val.length > 0 )	return null ;
					break;
				case kValue :
					if( val.length is 0 )	return null ;
					break;
				case kOf :
					if( val.length is 0 )	return null ;
					if( val[0] is '=' ) 		val = val[1..$] ;
					if( val.length is 0 )	return null ;
					break;
				case kDebug :
					if( val.length > 0 && val[0] is '=' ) 		val = val[1..$] ;
					break;
				default:
					return null ;
			}
			return val ;
		}
		
		static Arg* Init(char[] key , uint type ) {
			auto self		= new Arg ;
			if(key !is null)
				self.key	= key.dup ;
			self.type		= type ;
			return self ; 
		}
		
		static private {
			bool match_default(Arg* arg, char[] _val ) {
				char[] val	= arg.getValue( _val ); 
				if( val is null ){
					return false ;
				}
				int iDone	= 1 ;
				scope(exit){
					arg.isDone(iDone) ;
				}
				switch( arg.vtype ){
					case vBool :
						break ;
					case vBool2:
						iDone	=  1 -  arg.isDone  ;
						break;
						
					case vInt :
						arg.number	= val ;
						break ;
					
					case vText :
						arg.text	= val ;
						break ;
					
					case vDebug :
					case vStrings :
					case vLazyDirs :
						val		= Txt.trim( val );
						if( val.length > 0  ){
							bool isDone	= false ;
							foreach( p ; arg.strings ){
								if( p.val == val ){
									isDone	= true ;
								}
							}
							if( !isDone ) {
								arg.strings		~= _Text.Init( val ) ;
							}
						}
						break;
						
					case vFlag :
						return match_flag(arg, val );
					
					case vDir :
					case vFile :
					case vPath :
						return match_file(arg, val );
					
					case vDirs :
					case vFiles :
					case vPaths :
						return match_files(arg, val );
					
					default:
						Stdout("missing key = `")( arg.key )(" type= ")( Int.toString(arg.type) )("`\n").flush;
						exit(0);
						return false ; 
				}
				return true ; 
			}
			
			bool match_flag(Arg* arg, char[] _val ){
				char[][] vals	= _Text.split( _val  ,  ';' );
				if( vals.length is 0 ){
					return false ;
				}
				auto p	= new _Flag ;
				p._all		= vals[0] ;
				if( vals.length > 1 ){
					p._release	= vals[1] ;
				}
				if( vals.length > 2 ){
					p._debug	= vals[2] ;
				}
				arg.flags	~= p ;
				return true ; 
			}
			
			bool match_file(Arg* arg, char[] _val ){
				if( _val.length < 1 ){
					return false ;
				}
				arg.file	= _val ;
				return true  ; 
			}
			
			bool match_files(Arg* arg, char[] _val ){
				char[][] vals	= _Text.split( _val  ,  ';' );
				if( vals.length is 0 ){
					return false ;
				}
				foreach( ref val ; vals ){
					if( val.length ){
						arg.files	~= _File.Init( val ) ;
					}
				}
				return true ; 
			}

		}
		
		void dump(){
			if( isDone is 0 ){
				return ;
			}
			Stdout(this.key)(" \t\t") ;
			switch( this.vtype ){
				case vBool2:
				case vBool :
					Stdout("true");
					break;
				case vText :
					Stdout( this.text );
					break;
				case vInt :
					Stdout( Int.toString(this.number ) );
					break;
				case vDebug :
					if( this.strings.length is 0 ){
						Stdout("true");
						break ;
					}
				case vStrings :
					foreach( z ; this.strings ){
						Stdout( z.val )(" , \n\t\t");
					}
					break;
					
				case vFlag :
					foreach( flag; this.flags){
						Stdout(" `")(flag._all)("` , `")( flag._release) ("` ,  `")( flag._debug )("` \n\t\t");
					}
					break;
					
				case vDir :
				case vFile :
				case vPath :
					Stdout("`")( file.toString ) ("`");
					break;
				
				case vDirs :
				case vFiles :
				case vPaths :
					foreach( _file; this.files ){
						Stdout("  `")( _file.toString ) ("` \n\t\t");
					}
					break;
				default:
					Stdout(" Error").flush;
					exit(0);
			}
			Stdout("\n");
		}
		
		void render(Array bu){
			switch( this.vtype ){
				case vBool:
				case vBool2:
					bu(this.key)("\n");
					break;
				case vText:
					bu(this.key)(this.text)("\n");
					break;
				case vDebug:
					if( this.strings.length is 0 ){
						bu(this.key)("\n");
					}else{
						foreach( text; this.strings ){
							if( Ary.contains(text.val, ' ') ){
								bu(this.key)("=\"")(text.val)("\"\n");
							}else{
								bu(this.key)("=")(text.val)("\n");
							}
						}
					}
					break;
				case vStrings:
					foreach( text; this.strings ){
						if( Ary.contains(text.val, ' ') ){
							bu(this.key)("\"")(text.val)("\"\n");
						}else{
							bu(this.key)(text.val)("\n");
						}
					}
					break;
				case vLazyDirs:
					foreach( text; this.strings) {
						char[] _dirs = text.val ;
						if( Txt.containsPattern(_dirs, G.Dmd_Dir_Tag ) ) {
							_dirs	= Txt.substitute(text.val, G.Dmd_Dir_Tag , G.Dmd_Dir_Val )  ;
						}
						foreach( _dir ; QuoteFruct.Init( _dirs , ';' ) ) {
							char[] dir	= _File.TruePath( _dir );
							if( Ary.contains(dir, ' ') ){
								bu(this.key)("\"")(dir)("\"\n");
							}else{
								bu(this.key)(dir)("\n");
							}
						}
					}
					break;
				case vFile:
				case vDir:
				case vPath:
					if( Ary.contains(this.file.toString, ' ') ){
						bu(this.key)("\"")(this.file.toString)("\"\n");
					}else{
						bu(this.key)(this.file.toString)("\n");
					}
					break ;
				case vFiles:
				case vDirs:
				case vPaths:
					foreach( _file ; this.files ){
						if( Ary.contains( _file.toString, ' ') ){
							bu(this.key)("\"")(_file.toString)("\"\n");
						}else{
							bu(this.key)(_file.toString)("\n");
						}
					}
					break ;
				default:
					Stdout("option ")(this.key)(" value error \n").flush;
					exit(0);
			}
		}
	}
	
	static bool is_file_char(char _char){
		return ( _char >= 'a' && _char <= 'z' ) || ( _char >= 'A' && _char <= 'Z' ) || ( _char >= '0' && _char <= '9' ) || _char == '.' || _char == '_' ;
	}
	
	static bool is_file_start(char _char){
		return ( _char >= 'a' && _char <= 'z' ) || ( _char >= 'A' && _char <= 'Z' ) || _char == '_' ;
	}
	
	bool is_file(char[] _file){
		if( _file is null ) return false ;
		_file	= Txt.trim(_file); 
		if( _file.length is 0 || _file.length  < 3 ) return false ;
		scope fp	= new FilePath(_file);
		if( !Ary.contains(G.All_Exts, fp.ext) )	return false ;
		
		if( Ary.contains(G.D_Exts, fp.ext)  ){
			if( !is_file_start(_file[0]) )	return false ;
			foreach( c ; _file[1..$] ){
				if( !is_file_char(c) ){
					return false ;
				}
			}
			d_sources	~= _File.Init(_file);
		}else{
			o_sources	~= _File.Init(_file);
		}
		if( !fp.exists ){
			char[] file	= Environment.toAbsolute( _file );
			Stdout(" file `")(file)("` is not exist \n").flush;
			exit(1);
		}
		return true  ;
	}
	
	Arg*[]	args ;
	_File*[]	d_sources ;
	_File*[]	o_sources ;
	char[][]	others ;
	
	this(){
		
	}
	
	Args add(Arg* arg){
		foreach( ref _arg ; this.args ){
			if( _arg.key == arg.key ){
				Stdout("dup key `")(arg.key)("` \n").flush ;
				exit(1);
			}
		}
		this.args	~= arg ;
		return this ;
	}
	
	void parse(char[][] args){
		foreach(ref arg; args){
			parse(arg);
		}
	}
	
	void parse(char[] val ){
		foreach( _arg ; this.args ){
			if( _arg.match(_arg, val) ){
				return  ;
			}
		}
		if( !is_file( val ) ){
			this.others	~= val.dup ;
		}
	}
	
	void parse_dmd(char[] val){
		foreach( _val ; QuoteFruct.Init(val, ';') ){
			bool	isMatched	= false ;
			foreach( _arg ; this.args ){
				if( _arg.xtype is xDmake ){
					continue ;
				}
				if( _arg.match(_arg, _val) ){
					isMatched	= true ;
					break ;
				}
			}
			if( !isMatched &&  !is_file( _val ) ){
				this.others	~= _val.dup ;
			}
		}
	}
	void parse_flag(){
		Arg* node		= get(`\flag=`);
		if( node is null ){
			return ;
		}
		bool	isDebug	= get(`-debug`) !is null ;
		foreach( flag; node.flags ){
			parse_dmd( flag._all );
			if( isDebug ){
				parse_dmd( flag._debug );
			}else{
				parse_dmd( flag._release );
			}
		}
	}
	
	static This Dmake(This p ){
		
		p.add(  Arg.Init(`\make=`,	xDmake | kValue | vFile )  ) ;
		p.add(  Arg.Init(`\dmd=`,	xDmake | kValue | vText )  ) ;
		p.add(  Arg.Init(`\path=`,	xDmake | kValue | vText )  ) ;
		p.add(  Arg.Init(`\link=`,	xDmake | kValue | vText )  ) ;
		p.add(  Arg.Init(`\lib=`,	xDmake | kValue | vStrings )  ) ;
		
		p.add(  Arg.Init(`\dll`,		xDmake | vBool )  ) ;
		p.add(  Arg.Init(`\gui`,		xDmake | vBool )  ) ;
		p.add(  Arg.Init(`\flag=`,	xDmake | kValue | vFlag )  ) ;
		p.add(  Arg.Init(`\args=`,	xDmake | kValue | vText )  ) ;
		p.add(  Arg.Init(`\exec`,	xDmake | vBool )  ) ;
		p.add(  Arg.Init(`\console`,	xDmake | vBool2 )  ) ;
		p.add(  Arg.Init(`\clean`,	xDmake | vBool2 )  ) ;
		p.add(  Arg.Init(`\+`,		xDmake | kOf | vDirs )  ) ;
		p.add(  Arg.Init(`\-`,		xDmake | kOf | vPaths )  ) ;
		p.add(  Arg.Init(`\@`,		xDmake | kValue | vStrings )  ) ;
		p.add(  Arg.Init(`\$`,		xDmake | kValue | vText )  ) ;
		return p ;
	}
	
	static This Dmd(This p ){
		p.add(  Arg.Init(`@`,			kValue | vStrings  )  ) ;
		p.add(  Arg.Init(`-c`,			vBool  )  ) ;
		p.add(  Arg.Init(`-cov`,		vBool  )  ) ;
		p.add(  Arg.Init(`-Dd`,			kOf | vDir  )  ) ;
		p.add(  Arg.Init(`-Df`,			kOf | vFile  )  ) ;
		p.add(  Arg.Init(`-D`,			vBool  )  ) ;
		
		p.add(  Arg.Init(`-d`,			vBool  )  ) ;
		
		p.add(  Arg.Init(`-debuglib=`,	kOf | vText  )  ) ;
		p.add(  Arg.Init(`-debug`,		kDebug | vDebug  )  ) ;
		
		p.add(  Arg.Init(`-defaultlib=`,	kValue | vText  )  ) ;
		p.add(  Arg.Init(`-deps=`,		kValue | vFile  )  ) ;
		
		
		
		
		p.add(  Arg.Init(`-gc`,			vBool  )  ) ;
		p.add(  Arg.Init(`-g`,			vBool  )  ) ;
		
		p.add(  Arg.Init(`-Hd`,			kOf | vDir  )  ) ;
		p.add(  Arg.Init(`-Hf`,			kOf | vFile  )  ) ;
		p.add(  Arg.Init(`-H`,			vText  )  ) ;
		
		p.add(  Arg.Init(`--help`,		vBool  )  ) ;
		
		p.add(  Arg.Init(`-I`,			kOf | vLazyDirs )  ) ;
		p.add(  Arg.Init(`-ignore`,		vBool  )  ) ;
		p.add(  Arg.Init(`-inline`,		vBool  )  ) ;
		p.add(  Arg.Init(`-J`,			kOf | vLazyDirs )  ) ;
		p.add(  Arg.Init(`-L`,			kOf | vStrings )  ) ;
		
		p.add(  Arg.Init(`-lib`,			vBool  )  ) ;
		p.add(  Arg.Init(`-man`,		vBool  )  ) ;
		p.add(  Arg.Init(`-map`,		vBool  )  ) ;
		p.add(  Arg.Init(`-nofloat`,		vBool  )  ) ;
		p.add(  Arg.Init(`-O`,			vBool  )  ) ;
		p.add(  Arg.Init(`-o-`,			vBool  )  ) ;
		p.add(  Arg.Init(`-od`,			kOf | vDir )  ) ;
		p.add(  Arg.Init(`-of`,			kOf | vFile )  ) ;
		p.add(  Arg.Init(`-op`,			vBool  )  ) ;
		p.add(  Arg.Init(`-profile`,		vBool  )  ) ;
		p.add(  Arg.Init(`-quiet`,		vBool  )  ) ;
		p.add(  Arg.Init(`-release`,		vBool  )  ) ;
		p.add(  Arg.Init(`-run `,		kValue | vText  )  ) ;

		p.add(  Arg.Init(`-unittest`,		vBool  )  ) ;
		p.add(  Arg.Init(`-v`,			vBool  )  ) ;
		p.add(  Arg.Init(`-v1`,			vBool  )  ) ;
		p.add(  Arg.Init(`-version=`,		kValue | vStrings  )  ) ;
		p.add(  Arg.Init(`-wi`,			vBool  )  ) ;
		p.add(  Arg.Init(`-w`,			vBool  )  ) ;
		
		p.add(  Arg.Init(`-Xf`,			kValue | vText  )  ) ;
		p.add(  Arg.Init(`-X`,			vBool  )  ) ;
		return p ;
	}
	
	Arg* get(char[] key){
		foreach( arg ; this.args ){
			if( arg.key == key ){
				if( arg.isDone is 0 ){
					return null ;
				}
				return arg ;
			}
		}
		return null ;
	}
	
	char[][] files(){
		char[][] all ;
		Arg* make	= get(`\make=`);
		if( make !is null ){
			all	~= make.file.toString ;
		}
		foreach( f; d_sources ){
			if( !Ary.contains(all,  f.toString) ){
				all	~= f.toString ;
			}
		}
		Arg* add	= get(`\+`);
		if( add !is null ){
			Arg* del	= get(`\-`);
			char[][] xs ;
			if( del !is null ){
				foreach( f ; del.files ){
					if( !Ary.contains(xs,  f.toString) ){
						xs	~= f.toString ;
					}
				}
			}
			foreach( f ; add.files ){
				auto fp	= new FilePath( f.toString );
				if( !fp.exists ){
					Stdout("search object `")( f.toString )("` is not exists \n").flush ;
					exit(0);
				}
				if( !fp.isFolder ){
					if( Ary.contains(G.D_Exts, fp.ext) ){
						if( !Ary.contains(all, fp.toString) ){
							all	~= fp.toString ;
						}
					}else{
						if( !Ary.contains(o_sources, f ) ){
							o_sources	~= f ;
						}
					}
					continue ;
				}
				auto fs	= new FileScan();
				fs.sweep(fp.toString, (FilePath p, bool isDir ){
					if( !isDir && p.ext != "d" ){
						return false ;
					}
					if( Ary.contains(xs, p.toString ) ){
						return false ;
					}
					if( !isDir ){
						if( !Ary.contains(all, p.toString ) ){
							all	~= p.toString.dup ;
						}
					}
					return true ;
				});
			}
		}
		
		foreach( f; o_sources ){
			if( !Ary.contains(all,  f.toString) ){
				all	~= f.toString ;
			}
		}
		return all ;
	}
	
	void get_args(Array bu){
		version(Windows){
			auto of	= get(`-of`);
			if( of !is null ){
				foreach(ref c; of.file.toString) if( c is '/' ) c = '\\' ;
			}
		}
		
		foreach( arg; args){
			if( !arg.isDone ) continue ;
			if( arg.xtype is xDmake) continue ;
			arg.render(bu) ;
		}
		
		auto node	= get(`\gui`);
		if( node !is null ){
			bu(G.gui_option)("\n");
		}
		
	}


}



struct Ini_Node {
	char[]	name ;
	bool		isDone ;
	bool		isStdlib ;
	char[][]	args ;
	
	static const default_name	= "global" ;
	static char[]		dmake_ini_file ;
	static Ini_Node*[]	list ;
	static Ini_Node*[]	std_list ;
	
	static  Ini_Node* get(char[] name, bool isGetNull = false ){
		foreach( _p ; list ){
			if( _p.name == name ){
				return _p ;
			}
		}
		if( isGetNull ){
			return null ;
		}
		Ini_Node* p 	= new Ini_Node ;
		p.name		= name.dup ;
		list			~= p ;
		return p ;
	}
	
	static  Ini_Node* get_std(char[] name, bool isGetNull = false ){
		foreach( _p ; std_list ){
			if( _p.name == name ){
				return _p ;
			}
		}
		if( isGetNull ){
			return null ;
		}
		Ini_Node* p 	= new Ini_Node ;
		p.name		= name.dup ;
		p.isStdlib		= true ;
		std_list		~= p ;
		return p ;
	}
	
	void AddLine(char[] line ){
		this.args	~= line.dup ;
	}
	
	void parse(Args args){
		if( !isDone ){
			args.parse( this.args );
			isDone	= true ;
		}
	}
	
	static void Load(char[] self_path){
		scope FilePath _self_path ;
		version(Windows){
			_self_path	= new FilePath(getThisPath()) ;
		}else{
			_self_path	= new FilePath( Environment.toAbsolute(self_path) ) ;
		}
		
		G.Dmake_Dir_Val	=  _self_path.parent .dup  ;
		dmake_ini_file	= (_self_path.parent  ~ "/" ~ _self_path.name ~ ".ini\0").dup [ 0 .. $-1] ;
		
		if( !Pth.exists(dmake_ini_file) ){
			Stdout("config file `")(dmake_ini_file)("` is not exists\n").flush;
			exit(1);
		}
		
		version(Windows){
			foreach(ref c; G.Dmake_Dir_Val ) if( c is '/' ) c = '\\' ;
		}
		
		scope da	= cast (char[]) File.get(dmake_ini_file);
		da		= Txt.substitute(da, G.Dmake_Dir_Tag , G.Dmake_Dir_Val );
		scope bu	= new Array(da.length );
		bu(da);
		scope _ls	= new Lines!(char)(bu);
		
		Ini_Node* node	= Ini_Node.get( Ini_Node.default_name );

		foreach(int line_i , ref _line; _ls){
			char[] line	= Txt.trim( _line );
			if( line.length is 0 || line[0] == ';' || line[0] == '#' ){
				continue ;
			}
			if( line.length > 2 && line[0] is '[' && line[$-1] is ']' ){
				line	= Txt.trim( line[1..$-1] );
				if( line.length > 0 ){
					if( line[0] is '$' && line.length > 1 ){
						node	= Ini_Node.get_std( line[1..$] );
					}else{
						node	= Ini_Node.get( line );
					}
				}
				continue ;
			}
			if( node.isStdlib ){
				if(
					 _Text.startWith(line, `\$`) 
						||
					 _Text.startWith(line, `\@`) 
						||
					 _Text.startWith(line, `\path`) 
				){
					Stdout("\\$ = [")( node.name )("] can't have line = `")(line)("` in file: `")(dmake_ini_file)("` line:")( Int.toString(line_i) )("\n").flush;
					exit(0);
				}
			}
			node.AddLine(line) ;
		}
		
		Ini_Node.get( Ini_Node.default_name ).parse( Dmake.dmake );
	}

	void dump(){
		Stdout("Ini_Node:")(name)("\n");
		foreach( arg; args ){
			Stdout("\t")(arg)("\n");
		}
	}
}

struct Dmake{
	static Args		dmake ;
	
	static char[]	dmd_file ;
	static char[]	dmd_ini_file ;
	
	static char[]	start_dir ;
	static char[]	conf_dir ;
	static char[]	of_file 	= null ;

	static void Init(char[] self_path){
		dmake	= new Args ;
		Args.Dmake( dmake );
		Args.Dmd( dmake );
		Ini_Node.Load(self_path) ; 
	}
	
	
	static void make(char[][] args){
		dmake.parse(args) ;
		bool isConfigured	= false ;
		bool isHasFile	= false ;
		while(!isConfigured){
			auto arg		= dmake.get(`\make=`) ;
			if( arg is null ){
				break ;
			}
			char[] file1		= conf_from_file( arg.file , isConfigured) ;
			if( isConfigured ){
				start_dir	= Env.cwd.toString.dup ;
			}
			isHasFile		= file1 !is null ;
			break ;
		}
		
		static void goDir(){
			auto node	= dmake.get(`\make=`);
			FilePath fp 	= null ;
			if( node !is null ){
				fp	= new FilePath(node.file.toString) ;
			}else{
				if( dmake.d_sources.length > 0 ){
					fp	= new FilePath(dmake.d_sources[0].toString);
				}
			}
			Env.cwd(fp.parent) ;
			start_dir	= Env.cwd.toString.dup ;
		}
		
		while(!isConfigured){
			isConfigured	= conf_from_dir ;
			if( isConfigured ){
				auto node	= dmake.get(`\+`);
				if( node is null ){
					goDir;
				}else{
					conf_dir	= Env.cwd.toString.dup ;
				}
			}
			break;
		}
		
		while( !isConfigured ){
			if( dmake.d_sources.length > 0 ){
				char[] file1		= conf_from_file( dmake.d_sources[0] , isConfigured ) ;
				if( !isHasFile ){
					isHasFile		= file1 !is null ;
				}
				if( isConfigured ){
					goDir();
				}
			}
			break;
		}
		
		// if( !isHasFile )
		if( !isConfigured ){
			Stdout("no source to make\n").flush ;
			exit(1);
		}
	}
	
	
	static char[] conf_from_file(_File* _file, ref bool isConfigured){
		FilePath fp	= new FilePath(_file.toString) ;
		
		if( !fp.exists && fp.ext == "" ){
			fp	= new FilePath( _file.toString ~ ".d") ;
		}
		if( !fp.exists ){
			return null ;
		}
		if( !Ary.contains(G.D_Exts, fp.ext ) ){
			return null ;
		}

		scope da	= cast(char[]) File.get(fp.toString);
		int i		= Ary.find(da, '\n');
		int j		= Ary.find(da, '\r');
		if( j < i ){
			i	= j ;
		}
		scope ln	= Txt.trim( da[0..i] );
		
		if( ln.length > 3 ){
			if( ln[0] is 0xEF && ln[1] is 0xBB && ln[2] is 0xBF  || ln[0] is 0xBF && ln[1] is 0xBB && ln[2] is  0xEF ){
				ln	= Txt.trim(ln[3..$]);
			}
		}

		if( ln.length >= 3 && ln[0] is '/' && ln[1] is  '/' && ln[2] is ':' ){
			isConfigured	= true ;
			foreach( arg ; QuoteFruct.Init( ln[3..$] ) ){
				dmake.parse( arg );
			}
		}
		return fp.toString ;
	}
	
	static bool conf_from_dir (){
		char[] cwd	= Env.cwd.toString.dup  ;
		for( int i = 0 ; i < G.seek_deep ; i++ ){
			FilePath _cwd	= Env.cwd ;
			if( Pth.exists(G.conf_file) ){
				scope da	= cast(char[]) File.get(G.conf_file);
				foreach(_line; QuoteFruct.Init(da, '\n')){
					_line	= Txt.trim(_line);
					if( _line.length is 0 || _line[0] is ';' || _line[0] is '#' ) continue ;
					dmake.parse(_line);
				}
				return true ;
			}
			Env.cwd ("..");
		}
		Env.cwd (cwd);
		return false ;
	}
	
	
	static void pre_build(){
		Ini_Node*	ini_node;
		Args.Arg*	node ;		
		for( Args.Arg* arg = dmake.get(`\@`); arg !is null; arg = dmake.get(`\@`) ){
			if( arg.strings.length is 0 ){
				break ;
			}
			_Text*[] dup	= arg.strings.dup ;
			arg.strings.length	= 0 ;
			foreach( _ini_node ; dup){
				ini_node		= Ini_Node.get( _ini_node.val , true ) ;
				if( ini_node is null ){
					Stdout("\\@ = [")(_ini_node.val)("] is not defined in `")( Ini_Node.dmake_ini_file )("` \n").flush ;
					exit(0);
				}
				ini_node.parse(dmake);
			}
		}
		
		
		node		= dmake.get(`\$`) ;
		if( node is null ){
			Stdout("\\$ is required\n").flush;
			exit(0);
		}
		ini_node	= Ini_Node.get_std(node.text, true);
		if( ini_node is null ){
			Stdout("\\$ = [$")( node.text )("] is not defined in `")( Ini_Node.dmake_ini_file )("` \n").flush;
			exit(0);
		}
		
		auto dmd_args = new Args ;
		Args.Dmake( dmd_args );
		Args.Dmd( dmd_args );
		
		ini_node.parse( dmd_args );

		
		foreach( dmd_arg ; dmd_args.args ){
			if( !dmd_arg.isDone ) continue ;
			if( dmd_arg.xtype !is Args.xDmake ){
				continue ;
			}
			Args.Arg* dmake_arg = null ; 
			foreach( _dmake_arg ; dmake.args ){
				if( _dmake_arg.key == dmd_arg.key ){
					dmake_arg	= _dmake_arg ;
					break;
				}
			}
			if( dmake_arg is null ) continue ;
			uint isDone	= dmake_arg.isDone ;
			dmake_arg.isDone( true ) ;
			switch( dmd_arg.vtype ){
				case Args.vBool :	break;
				case Args.vBool2:
					isDone	-= cast(uint) dmd_arg.isDone ;
					dmake_arg.isDone( isDone   ) ;
					break;
				case Args.vText :
					dmake_arg.text( dmd_arg.text ) ;
					break;
				case Args.vInt :
					dmake_arg.number( Int.toString(dmd_arg.number) ) ;
					break;
				case Args.vDebug :
					if( dmd_arg.strings.length is 0 )		break ;
				case Args.vStrings :
					foreach( z ; dmd_arg.strings ){
						bool isHave = false ;
						foreach( _z ; dmake_arg.strings ){
							if( _z.val == z.val ){
								isHave	= true ;
								break;
							}
						}
						if( !isHave ){
							dmake_arg.strings  ~= z ;
						}
					}
					break;
					
				case Args.vFlag :
					foreach( flag; dmd_arg.flags ){
						dmake_arg.flags  ~= flag ;
					}
					break;
					
				case Args.vDir :
				case Args.vFile :
				case Args.vPath :
					dmake_arg._file	= dmd_arg._file	 ;
					break;
				
				case Args.vDirs :
				case Args.vFiles :
				case Args.vPaths :
					foreach( _file; dmd_arg.files ){
						bool isHave = false ;
						foreach( __file; dmake_arg.files ){
							if( __file.toString == _file.toString ){
								isHave	= true ;
								break ;
							}
						}
						if( !isHave ){
							dmake_arg.files ~= _file ;
						}
					}
					break;
				default:
					Stdout(" Error : ")( Int.toString(__LINE__) ).flush;
					exit(0);
			}
		}
		
		find_dmd();
		
		scope bu = new Array(1024, 1024 * 4 );
		bu("[Version]\n")
			("version=7.51 Build 020\n\n")
			("[Environment]\nLIB=") ;

		int pi	= bu.limit ;
		node	= dmake.get(`\lib=`) ;
		if( node !is null ){
			foreach_reverse( txt ; node.strings ){
				foreach( __txt; QuoteFruct.Init( txt.val , ';' ) ) {
					char[] _txt	= Txt.trim(__txt);
					if( _txt.length > 0 && _txt[0] is '"' ) _txt = _txt[1..$];
					if( _txt.length > 0 && _txt[$-1] is '"' ) _txt = _txt[0..$-1];
					if( Txt.containsPattern(_txt, G.Dmd_Dir_Tag ) ) {
						_txt	=Txt.substitute(_txt, G.Dmd_Dir_Tag , G.Dmd_Dir_Val );
					}
					char[] _pth = _File.TruePath(_txt) ;
					if( !Pth.exists( _pth ) ){
						char[] _pth2 = _File.TruePath( _Text.strip(__txt) ) ;
						if( !Pth.exists( _pth2 ) ){
							Stdout("lib_path `")(_pth)("` is not exist\n").flush;
							continue ;
						}
					}
					version(Windows) foreach(ref c; _pth) if ( c is '/' ) c = '\\' ;
					bu(_pth)(";");
				}
			}
		}
		if( bu.limit > pi ){
			( cast(char*) &bu.slice[$-1])[0]	= '\n';
		}else{
			bu("%@P%\\..\\lib\n");
		}
		
		bu("DFLAGS=");
		pi	= bu.limit ;
		dmd_args.get_args(bu);
		if( bu.limit > pi  ){
			char[] dflag	= cast(char[]) bu.slice()[ pi .. $ ]  ;
			foreach( ref c; dflag) if (c is '\n' ) c = ' ' ;
			( cast(char*) &bu.slice[$-1])[0]	= '\n';
		}else{
			bu("-I%@P%\\..\\import\n");
		}
		
		bu("LINKCMD=");
		pi	= bu.limit ;
		node	= dmake.get(`\link=`) ;
		if( node !is null ){
			char[] _link	= node.text ;
			if( Txt.containsPattern(_link, G.Dmd_Dir_Tag ) ) {
				_link	=Txt.substitute(_link, G.Dmd_Dir_Tag , G.Dmd_Dir_Val );
			}
			_link	= _File.TruePath(_link);
			version(Windows) foreach( ref c ; _link) if ( c is '/' ) c = '\\' ;
			bu(_link);
		}
		if( bu.limit == pi ){
			bu("%@P%\\link.exe\n");
		}
		
		File.set(Dmake.dmd_ini_file , bu.slice);
		
		dmake.parse_flag ;
	}
	
	static void build(){
		pre_build ;
		
		auto all	= dmake.files ;
		if( all.length is 0 ){
			Stdout("no sources \n ").flush;
			exit(0);
		}
		
		char[] base_dir	= start_dir ;
		if( base_dir is null | base_dir.length is 0 ){
			base_dir	= conf_dir ;
		}
		if( base_dir is null | base_dir.length is 0 ){
			base_dir	= Env.cwd.toString.dup  ;
		}
		Args.Arg* node	= dmake.get(`-of`);
		if( node !is null ){
			get_of(node.file.toString );
		}
		if( of_file is null ){
			get_of( all[0] , true );
		}
		if( of_file is null ){
			Stdout("no of_file \n ").flush;
			exit(0);
		}
		
		if( dmake.get(`\exec`) !is null ){
			exec_console();
			return ;
		}
		
		

		Array bu	= new Array(1024, 1024);
		bu(" ") ;
		foreach( f; all){
			bu(_File.RelPath(base_dir ,f) )("\n");
		}
		dmake.get_args(bu);
		foreach( o ; dmake.others ){
			bu(o)("\n");
		}
		Environment.cwd(base_dir);
		
		
		// start build 
		bool isClean	= dmake.get(`\clean`) !is null ;
		bool isArgFile	= false ;
		char[] args		= cast(char[]) bu.slice ;
		if( args.length ) args[$-1]	= 0 ;
		if( args.length > 1024 ){
			isArgFile	= true ;
			File.set(G.dmd_arg_file[1..$], args[1 .. $] );
			args	= " " ~ G.dmd_arg_file ;
		}else{
			foreach(ref c; args) if ( c is '\n' ) c = ' ' ;
		}
		static void DelFile(char[] file){
			if( file !is null ) {
				if( Pth.exists( file ) )
					Pth.remove(file);
			}
		}
		
		
		scope(exit){
			if( isClean ){
				scope fp	= new FilePath( of_file.dup );
				char[] _fp	= (fp.parent() ~ "/" ~ fp.name).dup  ;
				DelFile(_fp ~ ".obj");
				DelFile(_fp ~ ".map");
				char[] _f2	= fp.name() ;
				DelFile(_f2 ~ ".map" );
				DelFile(_f2 ~ ".obj" );
				if( isArgFile  ){
					DelFile(G.dmd_arg_file[1..$]);
				}
			}
		}
		
		exec0(Dmake.dmd_file, args, true );
		
	}
	
	static void find_dmd(){
		static char[] get_dmd_name(){
			scope FilePath	fp ;
			auto node		= dmake.get(`\dmd=`);
			if( node !is null ){
				fp	= new FilePath(node.text) ;
			}else{
				fp	= new FilePath(G.default_dmd);
			}
			if( fp.ext != G.Exe_Ext ){
				return fp.name ~ G.Exe_Ext ;
			}
			return fp.toString ;
		}
		static char[][] get_paths(){
			auto node		= dmake.get(`\path=`);
			if( node !is null ){
				return Txt.split(node.text, ";");
			}
			return null ;
		}
		
		static char[] get_dmd(char[][] paths, char[] dmd_name){
			foreach( _path; paths ){
				_path		= Txt.trim(_path);
				if( _path.length is 0 ) continue ;
				char[] path	=  _path  ~ "/" ~  dmd_name;
				scope fp	= new FilePath( path );
				if( fp.exists ){
					return fp.toString.dup ;
				}
			}
			return null ;
		}
		
		char[][] env_paths	= Txt.split(Environment.get(`path`) , `;` );
		char[][] conf_paths	= get_paths ;
		
		char[] dmd_name	= get_dmd_name ;
		char[] _dmd_file		= get_dmd(conf_paths, dmd_name );
		if( _dmd_file is null ){
			_dmd_file		= get_dmd(env_paths, dmd_name );
		}
		if( _dmd_file is null ){
			Stdout("`")(dmd_name)("` is not exists \n").flush;
			exit(0);
		}
		
		char[][] _paths ;
		
		foreach( _path;  conf_paths ){
			_path	= Txt.trim(_path);
			if( _path.length is 0 ) continue ;
			if( ! Ary.contains(_paths, _path) ){
				_paths	~= _path ;
			}
		}
		foreach( _path; env_paths ){
			_path	= Txt.trim(_path);
			if( _path.length is 0 ) continue ;
			if( ! Ary.contains(_paths, _path) ){
				_paths	~= _path ;
			}
		}
		Environment.set(`path`, Txt.join(_paths, ";") ) ;
		Dmake.dmd_file	= _File.TruePath(_dmd_file) ;
		G.Dmd_Dir_Val	= Dmake.dmd_file[0.. Ary.rfind(Dmake.dmd_file, '/' ) ] .dup ;
		Dmake.dmd_ini_file
					=  G.Dmd_Dir_Val ~ `/` ~ G.dmd_ini  ;
		version(Windows){
			foreach(ref c ; G.Dmd_Dir_Val ) if (c is '/' ) c = '\\' ;
		}
	}
	
	static void exec_console(){
		char[] args	= null ;
		auto node	= dmake.get(`\args=`);
		if( node !is null ){
			args	= " " ~ _Text.strip( node.text );
		}
		exec0(of_file, args);
	}
	
	static void get_of(char[] file, bool is_d_source = false ){
		auto fp	= new FilePath( file );
		if( is_d_source && ! Ary.contains(G.D_Exts, fp.ext ) ){
			return ;
		}
		if( dmake.get(`-lib`) !is null ){
			of_file	= (fp.parent() ~ "/" ~ fp.name() ~ G.Lib_Ext ) .dup ;
		}else{
			of_file	= (fp.parent() ~ "/" ~ fp.name() ~ G.Exe_Ext ) .dup ;
		}
	}
}


static void exec0(char[] file, char[] args,  bool isCopyEnv = false ){
	static char[] toNullEndedBuffer(char[][char[]] src){
		char[] dest;
		foreach (k, v; src){
			dest ~= k ~ '=' ~ v ~ '\0';
		}
		dest ~= '\0';
		return dest;
	}
	wchar* pFile, pArgs, pDir	= null ;
	char*	pEnv	= null ;
	if( isCopyEnv ){
		pEnv	= toNullEndedBuffer( Environment.get) . ptr ;
	}
	pFile	= toString16z( toString16(file) );
	pArgs	= toString16z( toString16(args) );
	
	DWORD dwCreationFlags	=	CREATE_NEW_PROCESS_GROUP;
	
	STARTUPINFO si;
	si.cb			= STARTUPINFO.sizeof;
	si.dwFlags 		= STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
	
	bool isExec		= Dmake.dmake.get(`\exec`) !is null ;
	if( isExec ){
		si.wShowWindow	= SW_SHOW;
	}
	
	if( !isExec ){
		scope fp	= new FilePath(file) ;
		Stdout(fp.name)( fromString16z(pArgs) )("\n").flush;
	}
	
	if( isExec && Dmake.dmake.get(`\console`) !is null ){
		dwCreationFlags	|=	CREATE_NEW_CONSOLE;
	}else{		
		si.hStdInput	= GetStdHandle(STD_INPUT_HANDLE) ;
		si.hStdOutput	= GetStdHandle(STD_OUTPUT_HANDLE) ;
		si.hStdError		= GetStdHandle(STD_ERROR_HANDLE);
	}
	
	auto now= Clock.now ;
	
	PROCESS_INFORMATION pi;
	auto ret = CreateProcessW(
			  pFile,
			  pArgs ,
			  null, null,
			  TRUE,
			  dwCreationFlags ,
			  pEnv, 
			  pDir,
			  &si, 
			  &pi);
	ret	= WaitForSingleObject(pi.hProcess, INFINITE);
	if( WAIT_OBJECT_0 != ret ){
		TerminateProcess(pi.hProcess, 1);
	}else{
		uint exitcode;
		GetExitCodeProcess(pi.hProcess, &exitcode);
	}
	auto delta 	= Clock.now - now ;
	Stdout(">Time: ")( Int.toString(delta.millis) )("ms ").flush;
}
