extends ColorRect

class Interpreter:
	enum {
		VAR,
		BEGIN,
		END,
		LOAD,
		PUT,
		STORE,
		LABEL,
		CALL,
		SYSCALL
		RET,
		JZ,
	}
	const Text_to_enum={
		"VAR":VAR,
		"BEGIN":BEGIN,
		"END":END,
		"LOAD":LOAD,
		"PUT":PUT,
		"STORE":STORE,
		"LABEL":LABEL,
		"CALL":CALL,
		"SYSCALL":SYSCALL,
		"RET":RET,
		"JZ":JZ
	}
	var program:Array=[]
	var display:String=""
	
	
	func load_program(text_bytecode):
		var res=[]
		for text_instruction in text_bytecode:
			#print(text_instruction)
			var name=text_instruction[0]
			if not name in Text_to_enum.keys():
				print("ERROR can not interpret \"",name,"\"as interpreter instruction" )
				assert(false)
			var instruction=Text_to_enum[name]
			match instruction:
				BEGIN,END,RET:
					res.append([instruction])
				LOAD,PUT,STORE,LABEL,CALL,JZ,SYSCALL:
					res.append([instruction,text_instruction[1][0]])
				VAR:
					res.append([instruction,text_instruction[1][0],text_instruction[1][1]])
				_:
					print("ERROR, not in assembly:",text_instruction)
					assert(false)
		program=res
	
	var ip=0#Instruction Pointer
	var ended=false
	
	var variableStack:Array=[]
	var valueStack:Array=[]
	var returnStack:Array=[]
	var ERRORS=[]
	
	func execute_one_instruction():
		if ended:
			print("Program already ended")
			return
		if ip>=program.size():
			ended=true
			print("Program Ended")
			return
		var ins=program[ip]
		print("exe:",ins," at ",ip)
		match ins[0]:
			VAR:
				variableStack.append([ins[1],null,ins[2]])
			BEGIN:
				variableStack.append([null,"STACK_SEPARATOR"])
			END:
				while true:
					if valueStack.empty():
						print("ERROR: Can not end something that has no begining")
						assert(false)
					var v=variableStack.pop_back()
					if v[0]==null:
						break
			LOAD:
				var id=variableStack.size()-1
				while true:
					if variableStack[id][0]==ins[1]:
						break
					id-=1
					if id<0:
						print("ERROR: No varible named '",ins[1],"'")
						assert(false)
				valueStack.append(variableStack[id][1])
			PUT:
				valueStack.append(ins[1])
			STORE:
				var id=variableStack.size()-1
				while true:
					if variableStack[id][0]==ins[1]:
						break
					id-=1
					if id<0:
						print("ERROR: No varible named '",ins[1],"'")
						assert(false)
				variableStack[id][1]=valueStack.pop_back()
				if not is_allowed_value(variableStack[id]):
					ERRORS.append("Can not store \""+variableStack[id][1].replace('\n',"\\n")+"\" in int")
					ended=true
			LABEL:
				pass
			CALL:
				var succes=false
				
				for p_id in  range(program.size()):
					var i=program[p_id]
					if i[0]==LABEL:
						if i[1]==ins[1]:
							print("call:",i," at ",p_id," form ",program.size())
							returnStack.append(ip)
							ip=p_id
							succes=true
							break
				if not succes:
					if ins[1]=="print":
						var v=valueStack.pop_back()
						display+=String(v)
						ip+=1
					else:
						print("ERROR: No function named '",ins[1],"'")
						assert(false)
			SYSCALL:
				var arg2=float(valueStack.pop_back())
				var arg1=float(valueStack.pop_back())
				var res:float
				match ins[1]:
					"+":
						res=arg1+arg2
					"-":
						res=arg1-arg2
					"/":
						res=arg1/arg2
					"*":
						res=arg1*arg2
				valueStack.append(res)
			RET:
				if returnStack.empty():
					print("Error no return address")
					assert(false)
				ip=returnStack.pop_back()
			JZ:
				var v=valueStack.pop_back()
				if v==0 or v=="0" or v=="0.0":
					var succes=false
					for p_id in  range(program.size()):
						var i=program[p_id]
						if i[0]==LABEL:
							if i[1]==ins[1]:
								returnStack.append(ip)
								ip=p_id
								succes=true
								break
					if not succes:
						print("ERROR: No label named '",ins[1],"'")
						assert(false)
			_:
				assert(false)
		print("exe:",ins)
		match ins[0]:
			VAR,BEGIN,END,LOAD,PUT,STORE,LABEL,SYSCALL:
				ip+=1
			CALL,RET,JZ:
				pass
			_:
				assert(false)
			
	func get_variableStack():
		var res=""
		for v in variableStack:
			if not v[0]==null:
				if  not v[1]==null:
					res+=v[0]+":"+v[2]+"="+v[1]+"\n"
				else:
					res+=v[0]+":"+v[2]+"=UNDEFINED\n"				
			else:
				res+="________________\n"
		return res
		
	func get_valueStack():
		var res=""
		for v in valueStack:
			res+=v+"\n"
		return res
		
	func is_allowed_value(assign):
		var res=true
		if assign[2]=="Integer":
			print("assign to int")
			return assign[1].is_valid_integer()
		return res
			
func show_asm(text_bytecode,line):
	var res=""
	var id=0
	for text_instruction in text_bytecode:
		res+="[color=red]"if id==line else ""
		res+=text_instruction[0]+" "
		for t in text_instruction[1]:
			res+=t+" "
		res+="\n"
		res+="[/color]"if id==line else ""
		id+=1
	$result.bbcode_enabled=true
	$result.bbcode_text=res
	$result.scroll_to_line(line)


var text_bytecode:Array
var currentLine=0
var runtime
var instruction:Array

var source=""

func _ready():
	text_bytecode=$Compiler.compile($Source.text)
	source=$Source.text
	print("code size=",text_bytecode.size())
	
	show_asm(text_bytecode,0)
	
	#var s=String(bytecode)
	runtime=Interpreter.new()
	runtime.load_program(text_bytecode)
	print("code size=",runtime.program.size())
	
func show_program(from, to):
	$Source.text=""
	$Source.bbcode_enabled=true
	var res=""
	for i in range(source.length()):

		if i==from:
			res+="[color=red]"
		if i==to:
			res+="[/color]"
		res+=source[i]
	$Source.bbcode_text=res




func _on_RunButton_pressed():
	runtime.execute_one_instruction()
	$"VaribleStack/RichTextLabel".text=runtime.get_variableStack()
	$"ValueStack/RichTextLabel2".text=runtime.get_valueStack()
	$"Display/RichTextLabel3".text=runtime.display
	currentLine=runtime.ip
	show_asm(text_bytecode,currentLine)
	if runtime.ip<text_bytecode.size():
		var token=text_bytecode[runtime.ip][2]
		if token!=null:
			show_program(token.begin_offset,token.end_offset)
	if not runtime.ERRORS.empty():
		OS.alert(runtime.ERRORS.pop_back())
