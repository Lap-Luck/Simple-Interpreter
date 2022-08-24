extends Node

const VIEW:bool=false

enum {NONE,WHITESPACE,OPERATOR,STRING_LITERAL,STIRING_ESCAPE,IDENTIFIER,INTEGER_LITERAL,FLOAT_LITERAL,KEYWORD}
class Tokenizer:
	const KEYWORDS=["const","struct","static","if","else","for","break","while","return","typedef"]
	
	class Token:
		var text:=""
		var type:=WHITESPACE
		var begin_offset:int=0
		var end_offset:int=0
		func _to_string():
			if type in [NONE]:
				return "END"
			if type in [OPERATOR,KEYWORD,INTEGER_LITERAL,FLOAT_LITERAL]:
				return "< "+text+" >"
			if type in [STRING_LITERAL]:
				return "<'"+text+"'>"
			return "<["+text+"]>"
	var currentToken:Token=Token.new();
	var newToken:Token=Token.new();
	var tokens=[]
	func what(c):
		if c-ord('0')>=0 and ord('9')-c>=0:
			return '0'
		if c-ord('a')>=0 and ord('z')-c>=0:
			return 'a'
		if c-ord('A')>=0 and ord('Z')-c>=0:
			return 'a'
		if char(c) in "_":
			return 'a'
		if  char(c) in "+-*/=!;.(){}[]":
			return '+'
		if  char(c) in " 	\n":
			return ' '
		if  char(c) in "\"":
			return "\""
		if  char(c) in "\\":
			return "\\"
		return '?'
		
	func tokenize(s:String):
		newToken.type=NONE
		var offset=0
		for ch in s:
			match [currentToken.type,what(ord(ch))]:
				#inteager behavior (see also default behavior)
				[INTEGER_LITERAL,'0']:
					currentToken.text+=ch
				[FLOAT_LITERAL,'0']:
					currentToken.text+=ch
				[INTEGER_LITERAL,'+']:
					if ch==".":
						currentToken.text+=ch
						currentToken.type=FLOAT_LITERAL
					else:
						newToken.text=ch
						newToken.type=OPERATOR
				#identyfier behavior(see also default behavior)
				[IDENTIFIER,'a']:
					currentToken.text+=ch
				[IDENTIFIER,'0']:
					currentToken.text+=ch
				# text parsing behavior
				[STRING_LITERAL,"\""]:
					newToken.type=WHITESPACE
				[STRING_LITERAL,"\\"]:
					currentToken.type=STIRING_ESCAPE
				[STIRING_ESCAPE,_]:
					var meaning=''
					match ch:
						'n':meaning='\n'
						't':meaning='\t'
						'\\':meaning='\\'
						'r':meaning='\r'
						_:
							print("TOKENIZER ERROR: Not recognize escape sequence \\",ch)
							assert(false)
					currentToken.text+=meaning
					currentToken.type=STRING_LITERAL
				[STRING_LITERAL,_]:
					currentToken.text+=ch
				# default behavior
				[_,'0']:
					newToken.type=INTEGER_LITERAL
					newToken.text+=ch
				[_,'a']:
					newToken.type=IDENTIFIER
					newToken.text+=ch
				[_,'+']:
					newToken.type=OPERATOR
					newToken.text+=ch
				[_,' ']:
					newToken.type=WHITESPACE
					newToken.text+=ch
				[_,'\"']:
					newToken.type=STRING_LITERAL
				[_,'\\']:
					print("TOKENIZER ERROR: stray \\")
					assert(false)
				[_,'?']:
					print("TOKENIZER ERROR:  not suported character=",ch," after ",currentToken.text)
					assert(false)
			if newToken.type!=NONE:
				if currentToken.type!=WHITESPACE:
					if currentToken.type==IDENTIFIER:
						if currentToken.text in KEYWORDS:
							currentToken.type=KEYWORD
					currentToken.end_offset=offset+1
					tokens.append(currentToken)
				currentToken=newToken
				currentToken.begin_offset=offset
				newToken=Token.new()
				newToken.type=NONE
			offset+=1
		if currentToken.type!=WHITESPACE:
			if currentToken.type==IDENTIFIER:
				if currentToken.text in KEYWORDS:
					currentToken.type=KEYWORD
			currentToken.end_offset=offset+1
			tokens.append(currentToken)
		tokens.append(newToken)# token None on the end
		return tokens

class Stack:
	var data=[]
	func put(e):
		data.push_back(e)
	func pop():
		return data.pop_back()
	func value():
		return data[-1]

class Parser:
	class PreParser:
		const DEBUG=true
		enum {
				E_PROGRAM,
				E_TYPEDEF,# use ot define type(with ;)
				E_FUNC,# whole function
				E_FUNC_DEC,# only declaration
				E_ARGS,#function arguments
				E_ARG,
				E_CODE_B,#statemts in {}
				E_STATS,#list of statements
				E_STAT,
				E_VALUE,
				E_BASIC_V,
				E_VALUE_MOD
			}
		
		#AST FORMAT
		#Array contining AST Node
		#AST Node is array with:
		#	emum E_(Expectation of parser)
		#	first_token_id
		#	last_token_id+1
		# NOTE: when two ids are eual AST Node represnts Empty set with position
		var AST=[]
		
		const to_text=["E_PROGRAM",
				"E_TYPEDEF",# use ot define type(with ;)
				"E_FUNC",# whole function
				"E_FUNC_DEC",# only declaration
				"E_ARGS",#function arguments
				"E_ARG",
				"E_CODE_B",#statemts in {}
				"E_STATS",#list of statements
				"E_STAT",
				"E_VALUE",
				"E_BASIC_V",
				"E_VALUE_MOD"]
		func rule_to_String(r):
			var res="("
			for s in r:
				if s[0]==1:
					res+=" and "+to_text[s[1]]
				else:
					res+=" and Type("+String(s[1])+")"+s[2]
			res+=")"
			return res
		#RULES FORMAT
		# dictionary traslating E_(Expectation of parser) and try number(from 1) to Array of CHECK 
		# CHECK is array first element is CHECK type 0 or 1
		# CHECK0 is in format [0, type ,text] and match if token has given type (if text then check if token has given text)
		# CHECK1 is in format [1,E_]
		
		var rules={
			[E_PROGRAM,1]:[[0,NONE,""]],
			[E_PROGRAM,2]:[[1,E_TYPEDEF],[1,E_PROGRAM]],
			[E_PROGRAM,3]:[[1,E_FUNC],[1,E_PROGRAM]],
			
			[E_TYPEDEF,1]:[[0,KEYWORD,"typedef"],[0,IDENTIFIER,""],[0,IDENTIFIER,""],[0,OPERATOR,";"]],
			[E_FUNC,1]:[[0,IDENTIFIER,""],[0,IDENTIFIER,""],[0,OPERATOR,"("],[1,E_ARGS],[0,OPERATOR,")"],[1,E_CODE_B]],
			[E_ARGS,1]:[[1,E_ARG],[0,OPERATOR,","],[1,E_ARGS]],
			[E_ARGS,2]:[[1,E_ARG]],
			[E_ARGS,3]:[],
			[E_ARG,1]:[[0,IDENTIFIER,""],[0,IDENTIFIER,""]],
			[E_CODE_B,1]:[[0,OPERATOR,"{"],[1,E_STATS],[0,OPERATOR,"}"]],
			[E_STATS,1]:[[1,E_STAT],[1,E_STATS]],
			[E_STATS,2]:[],
			[E_STAT,1]:[[0,IDENTIFIER,""],[0,IDENTIFIER,""],[0,OPERATOR,";"]],#varible declartion
			[E_STAT,2]:[[0,IDENTIFIER,""],[0,IDENTIFIER,""],[0,OPERATOR,"="],[1,E_VALUE],[0,OPERATOR,";"]],#variable assigment
			[E_STAT,3]:[[0,IDENTIFIER,""],[0,OPERATOR,"="],[1,E_VALUE],[0,OPERATOR,";"]],
			[E_STAT,4]:[[0,KEYWORD,"if"],[0,OPERATOR,"("],[1,E_VALUE],[0,OPERATOR,")"],[1,E_CODE_B]],#
			[E_STAT,5]:[[0,KEYWORD,"else"],[1,E_CODE_B]],
			[E_STAT,6]:[[0,KEYWORD,"while"],[0,OPERATOR,"("],[1,E_VALUE],[0,OPERATOR,")"],[1,E_CODE_B]],#while
			[E_STAT,7]:[[0,KEYWORD,"break"],[0,OPERATOR,";"]],#break
			[E_STAT,8]:[[1,E_VALUE],[0,OPERATOR,";"]],#break
			[E_STAT,9]:[[0,KEYWORD,"return"],[1,E_VALUE],[0,OPERATOR,";"]],#break
			[E_VALUE,1]:[[1,E_BASIC_V],[1,E_VALUE_MOD]],
			[E_BASIC_V,1]:[[0,STRING_LITERAL,""]],
			[E_BASIC_V,2]:[[0,INTEGER_LITERAL,""]],
			[E_BASIC_V,3]:[[0,FLOAT_LITERAL,""]],
			[E_BASIC_V,4]:[[0,IDENTIFIER,""]],
			[E_BASIC_V,5]:[[0,OPERATOR,"("],[1,E_VALUE],[0,OPERATOR,")"]],
			[E_VALUE_MOD,1]:[[0,OPERATOR,"+"],[1,E_VALUE]],
			[E_VALUE_MOD,2]:[[0,OPERATOR,"-"],[1,E_VALUE]],
			[E_VALUE_MOD,3]:[[0,OPERATOR,"*"],[1,E_VALUE]],
			[E_VALUE_MOD,4]:[[0,OPERATOR,"/"],[1,E_VALUE]],
			[E_VALUE_MOD,5]:[[0,OPERATOR,"("],[1,E_VALUE],[0,OPERATOR,")"]],
			[E_VALUE_MOD,6]:[]
		}
		
		var id:int=0
		var max_effort=120*10
		func effort():
			max_effort-=1
			if max_effort<0:
				assert(false)
		var backtruck_id=Stack.new();
		var tokens
		func preParse(tok):
			self.tokens=tok
			var t=expect(E_PROGRAM)
			if t:
				if DEBUG:print("HURRA")
			else:
				print("FAIL")
			return self.AST
			
		func expect(what):
			if what==E_PROGRAM:
				if DEBUG:print("READING")
			return expect_try(what,1)
			
			
		func expect_try(what,try_id):
			#assert(try_id!=3)
			var rules_key=[what,try_id]
			if not rules_key in rules:
				return false
			var rule=rules[rules_key]
			if DEBUG:print("Current Rule:",rule_to_String(rule)," CurrentToken:",tokens[id]," try:",try_id)
			var res=expect_rule(rule,what)
			if not res:
				return expect_try(what,try_id+1)
			else:
				if DEBUG:print("\t\t$$$$$$$$")
			return res
		
		func erase_AST(to):
			#while true:
			if true:
				if AST.empty():
					return
				if AST[-1][1]>=id:
					var d=AST.pop_back()
					if DEBUG:print("DEL ", to_text[d[0]])
				else:
					return
		
		func add_AST(what):
			if DEBUG:print("ADD ", to_text[what])
			AST.push_back([what,id,-1])
			
		func finish_add_AST():
			if DEBUG:print("FIN ", to_text[AST[-1][0]])
			AST[-1][-1]=id
		
		func expect_rule(rule,what)->bool:
			effort()
			backtruck_id.put(id)
			
			if DEBUG:print("ADD ", to_text[what])
			var AST_current_node=[what,id,-1]
			AST.push_back(AST_current_node)
			
			var res=expect_rule2(rule)
			if not res:
				id=backtruck_id.pop()
				erase_AST(id)
			else:
				AST_current_node[2]=id
				backtruck_id.pop()
			return res

		func expect_rule2(rule)->bool:
			for sub_rule in rule:
				if sub_rule[0]==0:
					var res= tokens[id].type==sub_rule[1] and (tokens[id].text==sub_rule[2] or sub_rule[2].empty())
					id+=1
					if DEBUG:print("\t"+"+"if res else"\t\t\t-"+rule_to_String(rule))
					if not res: return false
				if sub_rule[0]==1:
					if DEBUG:print("\tcall")
					var res=expect(sub_rule[1])
					if not res: 
						if DEBUG:print("<<<")
						return false
					else:
						if DEBUG:print("\t\t$$$$$$$$")
				if not sub_rule[0] in [0,1]:
					assert(false)
			return true
	# end of preparser
	
	# this is Main Parser potencialy bugy sometimes not checking token type
	# TODO rewrite this
	
	var tokens:Array
	var Program:=[]
	
	func group_to_String(group):
		var content=""
		var i=group[1]
		while i<group[2]:
			content+=tokens[i]._to_string()
			i+=1
		return PreParser.to_text[group[0]]+"("+content+")"
	
	func query_in_tree_groups(tree_groups,type,in_range):
		var res=[]
		for g in tree_groups:
			if type==-1 or g[0]==type:
				if in_range[0]==-1 or in_range[0]<=g[1]:
					if in_range[1]==-1 or in_range[1]>=g[2]:
						res.append(g)
		return res
	
	func read(g,id):
		if g[1]+id>=g[2]:
			assert(false)
		return tokens[g[1]+id].text
		
	func read_t(g,id):
		if g[1]+id>=g[2]:
			assert(false)
		return tokens[g[1]+id]
	
	enum {VOID,INT32,FLOAT32,FLOAT64}
	
	var known_types={
		"void":["void",VOID],
		"int":["Integer",INT32],
		"float":["Floating Point SP",FLOAT32],
		"double":["Floating Point DP",FLOAT64],
		}
	
	func parse_typedef(td):
		var value=read(td,1)
		var name=read(td,2)
		if not value in known_types.keys():
			print("Unknown type:",value)
			assert(false) 
		known_types[name]=known_types[value]
	
	var build_in_funcs=["print"]
	var defined_funcs=[]
	
	
	class Operator_Stack:
		#array containing:
		#disallow to execute privese operator
		#disallow to execute next operator
		
		#[11,10][20,21][30,0][11,10][21,20][0,0][1,1]	->	???????
		#[11,10][11,10][30,0][11,10][21,20][0,0][2,2]
		
		const presidence={
			")":[0,0],
			"+":[11,10],
			"-":[11,10],
			"*":[21,20],
			"/":[21,20],
			"(":[30,0],
			}
		var data=[]
		func put(op,metadata=[]):
			if not op in presidence.keys():
				assert(false)
			if data.empty():
				data.append([op,metadata])
				return []
			if presidence[data.back()[0]][1]<presidence[op][0]:
				data.append([op,metadata])
				return []
			if presidence[data.back()[0]][1]==presidence[op][0]:
				var op_in=data.pop_back()
				return [op_in,[op,metadata]]
			if presidence[data.back()[0]][1]>presidence[op][0]:
				var op_in=data.pop_back()
				var sub_res=self.put(op,metadata)
				var res=[op_in]
				for s in sub_res:
					res.append(s)
				return res
			assert(false)
		func pop():
			return [data.pop_back()] if not data.empty() else [] 
				
	func parse_value(t):
		if t[1]+1==t[2]:
			if tokens[t[1]].type==IDENTIFIER:
				Program.append(["LOAD",[read(t,0)],read_t(t,0)])
				return "LOAD "+read(t,0)
			else:
				Program.append(["PUT",[read(t,0)],read_t(t,0)])
				return "PUT "+read(t,0)
		else:
			var res=""
			var error=false
			var operators_stack=Operator_Stack.new()
			for t_id in range(t[1],t[2]):
				if  tokens[t_id].type==IDENTIFIER:
					res+=" LOAD "+tokens[t_id].text
					Program.append(["LOAD",[tokens[t_id].text],tokens[t_id]])
				else:
					if tokens[t_id].type!=OPERATOR:
						res+=" PUT "+tokens[t_id].text
						Program.append(["PUT",[tokens[t_id].text],tokens[t_id]])
					else:
						#TODO operator
						var ops=operators_stack.put(tokens[t_id].text,tokens[t_id])
						for op_d in ops:
							var op=op_d[0]
							if not op in["(",")"]:
								res+=" SYSCALL '"+op+"'"
								Program.append(["SYSCALL",[op],op_d[1]])
			while true:
				var op=operators_stack.pop()
				if op.empty(): break
				if not op[0][0] in["(",")"]:
					res+=" SYSCALL '"+op[0][0]+"'"
					Program.append(["SYSCALL",[op[0][0]],op[0][1]])
			if not error:
				return res
			else: 
				return "?"
	
	func default_value(t):
		if t==INT32:
			Program.append(["PUT",["0"],null])
			return "PUT "+"0"
			
		if t==FLOAT32:
			Program.append(["PUT",["0.0"],null])
			return "PUT "+"0.0"
	
	func parse_statment(s):
		var res=[]
		if read(s,0) in known_types:
			Program.append(["VAR",[read(s,1),known_types[read(s,0)][0]],read_t(s,0)])
			res.append("VAR "+read(s,1)+":"+known_types[read(s,0)][0]+"\n")
			if read(s,2)=="=":
				res.append(parse_value([-1,s[1]+3,s[2]-1])+" STORE "+read(s,1)+"\n")
				Program.append(["STORE",[read(s,1)],read_t(s,2)])
			else:
				if read(s,2)==";":
					res.append(default_value(known_types[read(s,0)][1])+" STORE "+read(s,1)+"\n")
					Program.append(["STORE",[read(s,1)],read_t(s,2)])
		else:
			if read(s,1)=="=":
				res.append(parse_value([-1,s[1]+2,s[2]-1])+" STORE "+read(s,0)+"\n")
				Program.append(["STORE",[read(s,0)],read_t(s,0)])
			else:
				if read(s,0)=="return":
					res.append(parse_value([-1,s[1]+1,s[2]-1])+" RET"+"\n")
					#TODO arbitrary number of end
					Program.append(["END",[],read_t(s,0)])
					Program.append(["END",[],read_t(s,0)])	
					Program.append(["RET",[],read_t(s,0)])
				else:
					if read(s,1)=="(":
						if read(s,s[2]-s[1]-1-1)==")":
							if 2<s[2]-s[1]-1-1:
								res.append(parse_value([-1,s[1]+2,s[1]+(s[2]-s[1]-1-1)])+" CALL "+read(s,0)+"\n")
								Program.append(["CALL",[read(s,0)],read_t(s,0)])
							if 2==s[2]-s[1]-1-1:
								res.append("PUT void CALL "+read(s,0))
								Program.append(["CALL",[read(s,0)],read_t(s,0)])
							if 2>s[2]-s[1]-1-1:
								assert(false)
						else:
							res.append("?\n")
					else:
						res.append("?\n")
		return res
	
	var jump_id=0
	
	func parse_meta_statment(s):
		var res=""
		if read(s,0)=="if":
			if read(s,1)=="(":
				var end_offset=2
				while(not read(s,end_offset)==")"):
					end_offset+=1
				jump_id+=1
				if end_offset>2:
					res+=parse_value([-1,s[1]+2,s[1]+end_offset])
				else:
					res+="0"# false on empty if????????????
				res+=" JZ "+"END_BLOCK"+String(jump_id)+"\n"
				Program.append(["JZ",["END_BLOCK"+String(jump_id)],read_t(s,0)])
			else:
				res="?"
		else:
			res="?"
		return [res,"Label: END_BLOCK"+String(jump_id)+"\n",["LABEL",["END_BLOCK"+String(jump_id)],read_t(s,s[2]-s[1]-1)]]
	
	var statments_ending=[]
	
	func parse(t):
		
		
		#TODO result assembly in Program
		
		Program.append(["CALL",["main"],null])
		Program.append(["PUT",["0"],null])
		Program.append(["JZ",["END"],null])
		
		
		
		
		#generate Abstract Syntax Tree but in very raf form
		tokens=t
		var p=PreParser.new()
		var raf_tree_grups=p.preParse(tokens)
		################################
		
		var tree=[]
		var info=""
		
		var typedefs=query_in_tree_groups(raf_tree_grups,PreParser.E_TYPEDEF,[-1,-1])
		var funcs=query_in_tree_groups(raf_tree_grups,PreParser.E_FUNC,[-1,-1])
		
		info+="<TYPEDEF>\n"
		for t in typedefs:
			self.parse_typedef(t)
			info+="\t"+group_to_String(t)+"\n"
		info+="<\\TYPEDEF>\n\n"
		if VIEW:print(known_types)
		for f in funcs:
			defined_funcs.append(read(f,1))
		info+="<FUNCS>\n"
		for f in funcs:
			Program.append(["LABEL",[read(f,1)],read_t(f,1)])
			Program.append(["BEGIN",[],read_t(f,2)])
			
			info+="\t<"+read(f,1)+">\n"#tokens[f[1]+1].text
			var args=query_in_tree_groups(raf_tree_grups,PreParser.E_ARG,[f[1],f[2]])
			for arg in args:
				Program.append(["VAR",[read(arg,1),known_types[read(arg,0)][0]],read_t(arg,1)])
				#TODO thout about arguments order
				Program.append(["STORE",[read(arg,1)],read_t(arg,1)])
				info+="\t\t"+"ARG "+read(arg,1)+":"+known_types[read(arg,0)][0]+"\n"
			Program.append(["BEGIN",[],read_t(f,1)])
			info+="\t\t"+"RET "+known_types[read(f,0)][0]+"\n"
			var statements=query_in_tree_groups(raf_tree_grups,PreParser.E_STAT,[f[1],f[2]])
			info+="\t\tBEGIN\n"
			for s in statements:
				for e_id in range(statments_ending.size()):
					var e=statments_ending[e_id]
					if e[1]<s[1]:
						#info+="\t\t\t"+"END_BLOCK"+"\n"
						var e_raf=statments_ending.pop_at(e_id)
						var ending=e_raf[0]
						Program.append(e_raf[2])
						info+="\t\t\t"+ending
				
				var subs=query_in_tree_groups(raf_tree_grups,PreParser.E_STAT,[s[1]+1,s[2]])
				if subs.empty():
					info+="\t\t\t\t"+group_to_String(s)+"\n"
					for ps in parse_statment(s):
						info+="\t\t\t\t\t"+ps
				else:
					info+="\t\t\t"+group_to_String(s)+"\n"
					var ms=parse_meta_statment(s)
					info+="\t\t\t\t\t"+ms[0]
					statments_ending.append([ms[1],s[2]-1,ms[2]])
			info+="\t\tEND\n"
			info+="\t<\\"+read(f,1)+">\n"#tokens[f[1]+1].text

		info+="<\\FUNCS>\n\n"
		
		Program.append(["LABEL",["END"],null])
		if false:
			for g in raf_tree_grups:
				print("\t",group_to_String(g))
			
			for g in raf_tree_grups:
				if g[0]==PreParser.E_STAT:
					info+=group_to_String(g)+"\n"
					print("\t",group_to_String(g))
				else:
					pass
				#print(group_to_String(g))
		#for n in raf_tree_grups:
		#	var i=n[1]
		#	var content=""
		#	while i<n[2]:
		#		content+=tokens[i]._to_string()
		#		i+=1
		#	if not content.empty():
		#		tree.append(n)
		#		print()
		#	else:
		#		if not n[1]==n[2]:
		#			print("ERROR AST TYPE:",p.to_text[n[0]]," from ",n[1]," to ",n[2] )
		
		if VIEW:print(info)
		
		return [Program,info]

#MY_BYTYCODE:
#VAR "x" int  // make new variable
#BEGIN        // set scope for variables 
#END		  // destroy scope for variables
#LOAD "x"     // put value of x on expresion_stack
#STORE "y"    //pop value from expression_stack(Can pop value from before begin)
#CLEAR        //remove evry value that is on expresion_stack,that was put after BEGIN(also removes variable put on stack by subcalls)
#SYS_CALL "/" //remove some values from expression_stack and put the reult
#LABEL f:     //can be use to set program execution there 
#CALL "f"     //just go to f and preserve ability to return
#RET		 // return
#JZ "loop_end"//jump to given label


func compile(sourse):
	if VIEW:print("Compiling....................")
	var tokens=Tokenizer.new().tokenize(sourse)
	if VIEW:print(tokens)
	if VIEW:print("###############")
	var p=Parser.new()
	var parse_res=p.parse(tokens)
	if VIEW:print("Compiling..................END")
	#print(p.rules[[Parser.E_STAT,3]])
	var i=parse_res[1]
	var asm=parse_res[0]
	if VIEW:print("##############")
	if VIEW:print(asm)
	

	
	return asm
