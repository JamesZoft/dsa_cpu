library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity alu is

    generic
    (
        gate_delay: time;
        word_size:  positive
    );

    port
    (
        si:    in  std_logic                                  :=            'X';  -- signed integers
        a_c:   in  std_logic                                  :=            'X';  -- A complement
        a_di:  in  std_logic_vector((word_size - 1) downto 0) := (others => 'X'); -- A data in
        b_c:   in  std_logic                                  :=            'X';  -- B complement
        b_di:  in  std_logic_vector((word_size - 1) downto 0) := (others => 'X'); -- B data in
        c_in:  in  std_logic                                  :=            'X';  -- carry in
        s_do:  out std_logic_vector((word_size - 1) downto 0) := (others => '0'); -- sum data out
        c_out: out std_logic                                  :=            '0'   -- carry out
    );

end alu;

architecture rtl of alu is

  signal internal_a_di : std_logic_vector(word_size downto 0) := (others => '0');
  signal internal_b_di : std_logic_vector(word_size downto 0) := (others => '0');
  
  signal int_a_di : std_logic_vector(word_size downto 0) := (others => '0');
  signal int_b_di : std_logic_vector(word_size downto 0) := (others => '0');
  
  signal internal_result : std_logic_vector(word_size downto 0) := (others => '0');
  signal internal_small_result : std_logic_vector((word_size - 1) downto 0) := (others => '0');

begin

internal_small_result <= internal_result((word_size - 1) downto 0);

  process(si, a_c, a_di, b_c, b_di, c_in, internal_a_di, internal_b_di, internal_result, int_a_di, int_b_di)
  begin
  
    int_a_di <= ('0' & a_di);
    int_b_di <= ('0' & b_di);
  
    if(a_c = '1') then
      
      internal_a_di <= (not int_a_di);
      
    else
    
      internal_a_di <= int_a_di;
      
    end if;
    
    if(b_c = '1') then 
    
      internal_b_di <= (not int_b_di);
      
    else
    
      internal_b_di <= int_b_di;
      
    end if;
      
    if(si = '0') then
      
      if(c_in = '1') then
        
        internal_result <= std_logic_vector( (unsigned(internal_a_di) + unsigned(internal_b_di)) + 1);
        
      else
      
        internal_result <= std_logic_vector( unsigned(internal_a_di) + unsigned(internal_b_di) );
        
      end if;
      
      c_out <= internal_result(word_size);
        
    else
    
       if(c_in = '1') then
        
        internal_result <= std_logic_vector( (signed(internal_a_di) + signed(internal_b_di)) + 1);
        
      else
      
        internal_result <= std_logic_vector( signed(internal_a_di) + signed(internal_b_di) );
        
      end if;
      
      c_out <= internal_a_di(word_size) xor internal_b_di(word_size);
    
    end if;
    
    s_do <= internal_result((word_size - 1) downto 0);
  
  end process;

end rtl;
