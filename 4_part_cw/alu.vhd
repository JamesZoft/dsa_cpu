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

    signal z_out: std_logic_vector(word_size downto 0) := (others => '0');

begin

    process (si, a_c, a_di, b_c, b_di, c_in)
        variable a_c_mask:  std_logic_vector(word_size downto 0);
        variable b_c_mask:  std_logic_vector(word_size downto 0);
        variable c_in_mask: std_logic_vector(word_size downto 0);
    begin
        a_c_mask  := (others => a_c);
        b_c_mask  := (others => b_c);
        c_in_mask := (0 => c_in, others => '0');
        
        if (si = '1') then
            z_out     <= std_logic_vector(  signed((a_di(word_size - 1) & a_di) xor a_c_mask) + 
                                            signed((b_di(word_size - 1) & b_di) xor b_c_mask) +   signed(c_in_mask));
        else
            z_out     <= std_logic_vector(unsigned(('0'                 & a_di) xor a_c_mask) + 
                                          unsigned(('0'                 & b_di) xor b_c_mask) + unsigned(c_in_mask));
        end if;

   end process;

    s_do  <= z_out((word_size - 1) downto 0);
    c_out <= z_out( word_size);
end rtl;
