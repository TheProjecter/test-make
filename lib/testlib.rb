def niceTime
  d=Time.now
  "%02d/%02d/%02d %02d:%02d:%02d"%[d.mday,d.mon,d.year%100,d.hour,d.min,d.sec]
end

def subSpaces
  if ENV["TESTER_SUB_LEVEL"]
    "  "*ENV["TESTER_SUB_LEVEL"].to_i
  else
    ""
  end
end

class Command
  attr_reader :command
  attr_accessor :exitStatus
  attr_accessor :sysStatus
  attr_accessor :subTest
  
  def initialize(command)
    @command=command
    @exitStatus=0
    @sysStatus="not run"
    @subTest=false
  end
end

class Test
  attr_reader :name, :env
  attr_accessor :saveFullEnv
  attr_reader :commands
  
  def initialize(name)
    raise unless name
    @name=name
    @env={}
    @saveFullEnv=false
    @successPatterns=[]
    @failPatterns=[]
    @commands=[]
  end
  
  def successLine(line)
    raise unless line
    @successPatterns << Regexp.compile("^"+Regexp.escape(line.to_s)+"$")
  end
  
  def successPattern(pattern)
    raise unless pattern
    if pattern.is_a? Regexp
      @successPatterns << pattern
    else
      @successPatterns << Regexp.compile(Regexp.escape(pattern.to_s))
    end
  end
  
  def failPattern(pattern)
    raise unless pattern
    if pattern.is_a? Regexp
      @failPatterns << pattern
    else
      @failPatterns << Regexp.compile(Regexp.escape(pattern.to_s))
    end
  end
  
  def command(cmdstr,*options)
    raise unless cmdstr
    if options.empty?
      options={}
    else
      options=options[0]
      raise unless options
      raise unless options.is_a? Hash
    end
    cmd=Command.new(cmdstr)
    if options[:exitStatus]
      cmd.exitStatus=options[:exitStatus]
    end
    if options[:subTest]
      cmd.subTest=options[:subTest]
    end
    @commands << cmd
  end
  
  def report(result,resultText)
    map={}
    
    map[:name]=@name
    map[:directory]=Dir.pwd.to_s
    
    env={}
    if saveFullEnv
      ENV.each_pair{
        | key, val |
        env[key.to_s]=val.to_s
      }
    else
      @env.each_pair {
        | key, val |
        env[key.to_s]=val.to_s
      }
    end
    
    map[:env]=env
    map[:envChanged]=@env.keys
    map[:commands]=[]
    @commands.each {
      | cmd |
      map[:commands] << {
        :commandString=>cmd.command,
        :expectExit=>true,
        :expectExitStatus=>cmd.exitStatus,
        :sysStatus=>cmd.sysStatus
      }
    }
    map[:successPatterns]=@successPatterns.collect{|x| x.inspect}
    map[:failPatterns]=@failPatterns.collect{|x| x.inspect}
    map[:summary]=result
    map[:output]=resultText
    
    File.open($output,'a') {
      | outp |
      outp.puts FijiConfig::dump(map)
    }
  end
  
  def runTest
    if name =~ $runPattern
      unless $verbose or $dotsOnly
        $stdout.print "#{subSpaces}#{niceTime} #{@name}: "
        $stdout.flush
      end
      
      $stderr.puts "> running test #{@name}" if $verbose

      oldEnvVals={}
      keysToRemove=[]
      @env.each_pair {
        | key, val |
        if ENV[key]
          oldEnvVals[key]=ENV[key]
        else
          keysToRemove << key
        end
        ENV[key]=val
      }
      
      foundSuccessPatterns={}
      foundFailPattern=false
      resultText=''
      result="SUCCESS"
      
      didSubTestStuff=false
      
      @commands.each {
        | cmd |
        # FIXME: better way of handling sub-tests:
        # - set an environment variable that contains 128 bits of randomness
        # - the input loop in popen waits for a signature that contains the 128 bits of randomness
        # - once received, subsequent input is read one byte at a time and immediately echoed
        # - if we detect that we're in a subtest, immediately write the 128 bits in the env var
        
        if cmd.subTest
          unless $verbose or $dotsOnly
            unless didSubTestStuff
              puts
              didSubTestStuff=true
            end
            if ENV["TESTER_SUB_LEVEL"]
              oldEnvVals["TESTER_SUB_LEVEL"]=ENV["TESTER_SUB_LEVEL"]
              ENV["TESTER_SUB_LEVEL"]=(ENV["TESTER_SUB_LEVEL"].to_i+1).to_s
            else
              ENV["TESTER_SUB_LEVEL"]=1.to_s
              keysToRemove << "TESTER_SUB_LEVEL"
            end
          end
        end
        
        if cmd.subTest
          cmdstr=cmd.command
        else
          cmdstr=cmd.command+" 2>&1"
        end
        $stderr.puts ">> #{cmdstr}" if $verbose
        
        if cmd.subTest
          system(cmdstr)
        else
          IO.popen(cmdstr,'r') {
            | inp |
            inp.each_line {
              | line |
              puts line if $verbose
              resultText << line
              @successPatterns.each {
                | expected |
                if line =~ expected
                  foundSuccessPatterns[expected.to_s]=true
                end
              }
              @failPatterns.each {
                | expected |
                if line =~ expected
                  foundFailPattern=true
                end
              }
            }
          }
        end
        
        cmd.sysStatus=sysresult=$?
        
        $stderr.puts "> System result: #{sysresult.inspect}" if $verbose

        if sysresult.exited?
          if sysresult.exitstatus==cmd.exitStatus
            # ok!
          else
            result="FAIL: exit=#{sysresult.exitstatus}"
            break
          end
        else
          result="FAIL: stat=#{$?}"
          break
        end
      }
      
      if result=="SUCCESS"
        unless @successPatterns.size==foundSuccessPatterns.size
          result="FAIL: bad output (s)"
        end
        if foundFailPattern
          result="FAIL: bad output (f)"
        end
      end
      
      $stderr.puts "> Result: #{result}" if $verbose
      
      report(result,resultText)
    
      oldEnvVals.each_pair {
        | key, val |
        ENV[key]=val
      }
      keysToRemove.each {
        | key |
        ENV.delete(key)
      }

      unless $verbose or didSubTestStuff
        if $dotsOnly
          if result=='SUCCESS'
            $stdout.print '.'
          else
            $stdout.print 'F'
          end
          $stdout.flush
        else
          if didSubTestStuff
            if result!='SUCCESS'
              puts "#{subSpaces}  #{result}"
            end
          else
            $stdout.puts result
          end
        end
      end
    else
      $stderr.puts "> skipping test #{$name}" if $verbose
    end
  end
end

def runTest(t)
  t.runTest
end

def resetDB(db)
  File.open(db,'w') {}
end

def summarize(db,all)
  def rpad(str,len)
    while str.length<len
      str+=' '
    end
    str
  end

  success=0
  total=0

  File.open(db,'r') {
    | inp |
    inp.each_line {
      | line |
      line.chomp!
      line.strip!
      unless line.empty?
        map=FijiConfig::parse(line)
        total+=1
        name=map['name']
        val=map['summary']
        thisSuccess=false
        if val=='SUCCESS' or val=='OK'
          thisSuccess=true
        end
        if thisSuccess
          success+=1
        end
        if all or not thisSuccess
          puts "#{rpad(val,22)} #{name}"
        end
      end
    }
  }

  if subSpaces==''
    puts "#{subSpaces}#{success}/#{total} TESTS PASSED."
  end

  if success!=total
    puts "#{total-success} TESTS FAILED!"
    puts "use localbin/recall <test name> to get details."
    return false
  else
    return true
  end
end


