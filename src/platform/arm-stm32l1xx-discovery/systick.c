void I2C_Tick(void);

void SysTick_Handler(void)
{ 
  I2C_Tick();
}
