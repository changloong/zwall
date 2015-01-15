//: -clean

module xw.json ;

import

	tango.core.Traits ,
	
	tango.io.device.Array ,
	tango.io.device.File ,
	
	tango.time.Clock ,
	tango.time.Time ,
	
	tango.text.convert.Layout ,
	Ary	= tango.core.Array ,
	Txt	= tango.text.Util ,
	Int	= tango.text.convert.Integer ,
	Flo	= tango.text.convert.Float ,
	Utf	= tango.text.convert.Utf ,
	
	tango.text.json.Json ,
	
	tango.io.Stdout ;
	
struct Textz {
	
	char[] 	buf ;
	int		pos , len  ;
	
	void set(char[] str){
		buf	= str ;
		pos	= 0 ;
		len	= str.length ;
	}
	
	char[] val(){
		return buf[ pos .. len ] ;
	}
	
	char[] tok(char _tok ){
		if( pos >= len ){
			return null ;
		}
		int _pos = pos ;
		for( int i = pos ; i < len; i++){
			if( buf[i] is _tok ){
				pos	= i+1 ;
				return buf[ _pos .. i ] ;
			}
		}
		pos	= len ;
		return buf[ _pos .. $ ] ;
	}
	
	
	char[] rtok(char _tok ){
		if( len <= pos ){
			return null ;
		}
		int _len	= len ;
		for( int i = len -1 ;  i > pos ; i-- ){
			if( buf[i] is _tok ){
				len	= i  ;
				return buf[ i +1 .. _len ] ;
				break;
			}
		}
		len	= pos ;
		return buf[ pos .. _len ] ;
	}
}

struct Jsonz {
	alias Json!(char).Type		JType ;
	alias Json!(char).JsonValue		JValue ;
	alias Json!(char).NameValue		JPair ;
	alias Json!(char).JsonObject	JObject ;

	private {
		Json!(char)
				json		= null ;
		JValue*	root  	= null ;
		JValue*	now  	= null ;
	}
	
	static Jsonz* Load(char[] file){
		char[] da	= cast(char[]) File.get(file);
		Jsonz* p	= new Jsonz ;
		p.json	= new Json!(char) ;
		try{
			p.root	= p.json.parse ( da ) ;
		}catch(Exception e) {
			return null ;
		}
		return p ;
	}
	
	void Save(){
		scope bu	= new Array(1024, 1024) ;
		root.print((char[] c) {bu(c);	}, "\t");
		Stdout.formatln("{}",  cast(char[]) bu.slice );
	}
	
	JValue* GetValue(char[] path){
		Textz t ;
		t.set( path ) ;
		return GetValue(&t);
	}
	
	private JValue* GetValue(Textz* t){
		if( root is null ){
			return null ;
		}
		JValue* node ;
		if( t.buf[0] is '/' ){
			t.tok('/');
			node	= root ;
		}else{
			node	= now is null ? root : now ;
		}
		JObject*	obj ;
		char[]	_k  	= null ;
		for( char[] k =  t.tok('/') ; k !is null; k =  t.tok('/') ){
			if( _k !is null ){
				obj	= node.toObject ;
				if( obj is null ){
					return null ;
				}
				node	= obj.value ( _k );
				if( node is null ){
					return null ;
				}
			}
			_k	= k ;
		}
		if( _k  !is null ){
			obj	= node.toObject ;
			if( obj is null ){
				return null ;
			}
			return obj.value ( _k );
		}
		return null ;
	}
	
	private JValue* CreateValue(char[] path){
		if( root is null ){
			root	=  json.object ;
		}
		
		char[]	_k  	= null ;
		JValue*	node	= root ;
		JObject*	obj	= null ;
		
		Textz t ;
		t.set(path);
		
		if( t.buf[0] is '/' ){
			node	= root ;
		}else{
			node	= now is null ? root : now ;
		}
		
		for( char[] k =  t.tok('/') ; k !is null; k =  t.tok('/') ){
			if( _k !is null  && _k != "" ){
				obj	= node.toObject ;
				if( obj is null ){
					return _CreateValue(&t, k, node) ;
				}
				node	= obj.value ( _k );
				if( node is null ){
					JValue* valz	= json.value(true) ;
					obj.append( json.pair( _k, valz) );
					return _CreateValue(&t, k, valz) ;
				}
			}
			_k	= k ;
		}
		
		if( obj !is null ){
			JValue* valz	= json.value(true) ;
			obj.append( json.pair(_k, valz ) );
			return valz ;
		}
		return null ;
	}
	
	private JValue* _CreateValue(Textz* t, char[] _key, JValue* _root ){
		JValue* 	v	= json.value( true ) ;
		JValue* 	_v 	= v ;
		for( char[] k = t.rtok('/') ; k !is null; k = t.rtok('/') ){
			if( k != "" ){
				v	= json.object(	json.pair( k, v )) ;
			}
		}
		_SetValue(_root, json.object(
				json.pair( _key, v )
			));
		return _v ;
	}
	
	Jsonz* setPath(char[] path){
		now		= GetValue(path) ;
		return this;
	}
	
	Jsonz* Set(T)( char[] path ,  T val  ){
		Textz  t;
		t.set(path) ;
		JValue* v	= GetValue( &t ) ;
		if( v is null ){
			v	= CreateValue( path ) ;
		}
		static if( is( T == bool) || isRealType!(T) || isIntegerType!(T) ||  is(ElementTypeOfArray!(T)==char)  ){
			v.set( val );
		}else static if( isPointerType!(T)  ){
			static if(  is( T == JValue* ) ){
				_SetValue(v, val );
			}else static if( is ( T == Jsonz*  ) ){
				_SetValue(v, val.root );
			}
		}else static if( isAssocArrayType!(T) ){
			JValue* valz		= json.object ;
			static assert(false, T.stringof );
		}else static if( isArrayType!(T) ){
			JValue[] Val	= new JValue[ val.length ];
			JValue*[] Valz	= new JValue*[ val.length ];
			foreach(int i, e ; val ){
				Valz[i]	= Val[i].set( e );
			}
			v.set( Valz );
		}else{
			static assert(false, T.stringof );
		}
		return this ;
	}
	
	static private void _SetValue(JValue*  o, JValue*  n){
		if( n is null ){
			o.reset;
		}else 
			switch(n.type){
				case JType.String :
				case JType.RawString :
						o.set( n.toString );
					break ;
				case JType.Number :
						o.set( n.toNumber );
					break;
				case JType.True :
				case JType.False :
						o.set( n.toBool );
					break;
				case JType.Object:
						o.set( n.toObject );
					break;
				case JType.	Array:
						o.set( n.toArray );
					break;
			}
	}
	
	char[] Str(char[] path){
		JValue* v = GetValue( path ) ;
		if( v ){
			return v.toString ;
		}
		return null ;
	}
	
	int Int(char[] path){
		JValue* v = GetValue( path ) ;
		if( v ){
			return cast(int) v.toNumber ;
		}
		return 0 ;
	}
}

void main(){
	auto p	= Jsonz.Load( `conf.js` ) ;
	p.setPath("/interfaces/lan");
	Stdout.formatln("value = `{}` ; \n ",  p.Str("if")   );
	char[] key1	= "/interfaces/wan/ip"  ;
	p.Set( key1 , "192.168.1.1" );
	p.Save ;
	
}