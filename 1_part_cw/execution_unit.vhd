library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.util.all;

entity execution_unit is

    generic
    (
        gate_delay: time;     -- delay per gate for simulation only
        word_size:  positive; -- width of data bus in bits
        rom_size:   positive; -- size of ROM in words
        ports_in:   positive; -- number of 8 bit wide input ports
        ports_out:  positive  -- number of 8 bit wide output ports
    );

    port
    (
        clk:           in  std_logic                                             :=            'X';  -- clock
        rst:           in  std_logic                                             :=            'X';  -- rst
        en:            in  std_logic                                             :=            'X';  -- enable

--synopsys synthesis_off
        test_pc:       out unsigned((n_bits(rom_size) - 1) downto 0)             := (others => 'X'); -- program counter
        test_opcode:   out std_logic_vector(7 downto 0)                          := (others => 'X'); -- instruction opcode
        test_ins_data: out std_logic_vector(word_size - 9 downto 0)              := (others => 'X'); -- instruction data
--synopsys synthesis_on

        rom_en:        out std_logic                                             	:=            'X';  -- ROM enable (set high when wanting to read)
        rom_addr:      out std_logic_vector((n_bits(rom_size - 1) - 1) downto 0) := (others => 'X'); -- ROM address to read
        rom_data:      in  std_logic_vector((word_size - 1) downto 0)            := (others => 'Z'); -- ROM data (the 8 digit hex word)

        io_in:         in  byte_vector((ports_in - 1) downto 0)                  := (others => byte_unknown); -- 8 bit wide input ports (buttons/switches/dcf/msf/rx)
        io_out:        out byte_vector((ports_out - 1) downto 0)                 := (others => byte_null)     -- 8 bit wide output ports

    );

end execution_unit;

architecture syn of execution_unit is

  signal curr_rom_en: std_logic	:= 'X';
  signal next_rom_en: std_logic := 'X';
  
  signal curr_io_out: byte_vector((ports_out - 1) downto 0) := (others => byte_null);
  signal next_io_out: byte_vector((ports_out - 1) downto 0) := (others => byte_null);
  
  signal internal_opcode: std_logic_vector(7 downto 0) := (others => 'X');
  
  signal io_out_port: std_logic_vector(7 downto 0) := (others => 'X');
  signal and_argument: std_logic_vector(7 downto 0) := (others => 'X');
  signal xor_argument: std_logic_vector(7 downto 0) := (others => 'X');
  
  signal curr_test_pc: std_logic_vector((n_bits(rom_size) - 1) downto 0) := (others => 'X');
  signal next_test_pc: std_logic_vector((n_bits(rom_size) - 1) downto 0) := (others => 'X');
  
  signal somesig: std_logic := '0';
  
  signal first_inst: std_logic := '1';
  signal next_first_inst: std_logic := '1';
  
  signal internal_test_ins_data: std_logic_vector(word_size - 9 downto 0) := (others => 'X');
  
  signal test_flag: std_logic := 'X';
  signal next_test_flag: std_logic := 'X';
  
  signal whee: std_logic := '0';
  
  signal delay: std_logic := '1';
  signal next_delay: std_logic := '1';
  
  signal lhs: std_logic_vector(7 downto 0);
  
  --signal left_hand_side: std_logic_vector(byte_vector(((ports_in - 1) downto 0)(to_integer(unsigned(std_logic_vector(7 downto 0)))))) := (others => 'X');
  
  
  
begin
io_out <= curr_io_out;	
rom_addr <= std_logic_vector(curr_test_pc);
test_pc <= (unsigned(curr_test_pc )	);
test_opcode <= internal_opcode;
internal_opcode <= rom_data(31 downto 24);
io_out_port <= rom_data(23 downto 16);
and_argument <= rom_data(15 downto 8);
xor_argument <= rom_data(7 downto 0);
internal_test_ins_data <= rom_data(23 downto 0);
test_ins_data <= internal_test_ins_data;
  
  
  process(clk, rst)
  begin
  
  	if (rst = '1') then -- If reset
  	
  		--curr_rom_en <= 'X';
  		curr_io_out <= (others => byte_null);
  		curr_test_pc <= (others => '0');
  		first_inst <= '1';
  		test_flag <= 'X';
  		delay <= '1';
  	
		elsif clk'event and (clk = '1') then	--On clock ri
		
			--curr_rom_en <= next_rom_en;
			curr_io_out <= next_io_out;
			curr_test_pc <= next_test_pc;
			first_inst <= next_first_inst;
			rom_en <= '1';
			test_flag <= next_test_flag;
			delay <= next_delay;
			
			--if(delay = '1') then
			--	curr_test_pc <= "000000";
			--	delay <= '0';
  		
  		--end if;
			
		end if;
  
  end process;
  
  process(rom_data, internal_opcode, curr_io_out, io_out_port, and_argument, xor_argument, curr_test_pc)
  
  	--variable lhs: std_logic_vector(7 downto 0);
  
  begin
  
  	
  
  	if (internal_opcode = "00000000") then --IUC
  		--stuff
  		
  	elsif (internal_opcode = "00000001") then --HUC
  		--stuff
  		
  	elsif (internal_opcode = "00000010") then --BUC
  		--stuff
  		
  	elsif (internal_opcode = "00000011") then --BIC
			
			if(test_flag = '1') then
																									--std_logic_vector((n_bits(rom_size) - 1) downto 0)
				next_test_pc <= std_logic_vector(internal_test_ins_data((n_bits(rom_size) - 1) downto 0));
				
			elsif(test_flag = '0') then
			
				next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);
				
			end if;
			
			--next_test_flag <= 'X';
  		
  	elsif (internal_opcode = "00000100") then --SET0
  		next_io_out(to_integer(unsigned(io_out_port))) <= std_logic_vector((curr_io_out(to_integer(unsigned(io_out_port)))) and and_argument) xor xor_argument;
  	  next_test_pc <= std_logic_vector(unsigned(curr_test_pc) + 1);  	  
  		
  	elsif (internal_opcode = "00000101") then --TSTI
  		lhs <= std_logic_vector((io_in(to_integer(unsigned(io_out_port))) and and_argument) xor xor_argument);
  		if (lhs = "00000000") then --It is zero, branch
			
				whee <= '0';
				next_test_flag <= '1';
				
			else --Don't branch
			
				whee <= '1';
				next_test_flag <= '0';
			
			end if;
  		
  	end if;
  	
  	
  	
  	--if(first_inst = '1') then
  		
  	--	next_test_pc <= "000000";
  	--	next_first_inst <= '0';
  		
  	--end if;
  
  end process;
  
  
    
end syn;
