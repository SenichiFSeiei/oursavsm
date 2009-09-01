#ifndef LIGHT_SETTINGS

#define NUM_LIGHT 4

// Begin ---------------------	Light Position ---------------------------------
#define LIGHT_POS0	D3DXVECTOR3(15.089104, 50.029869, -30.556995)//front
//#define LIGHT_POS1	D3DXVECTOR3(40.089104, 50.029869, 3.556995)//left
//#define LIGHT_POS2	D3DXVECTOR3(-40.089104, 50.029869, -0.556995)//right
#define LIGHT_POS1	D3DXVECTOR3(15.089104, 50.029869, 10.556995)//front
#define LIGHT_POS2	D3DXVECTOR3(-15.089104, 50.029869, -30.556995)//front
#define LIGHT_POS3	D3DXVECTOR3(-15.089104, 50.029869, 10.556995)//front
//#define LIGHT_POS3	D3DXVECTOR3(10.089104, 60.029869, -48.556995)//back
#define LIGHT_POS		{LIGHT_POS0,LIGHT_POS1,LIGHT_POS2,LIGHT_POS3};
// End ---------------------	Light Position ---------------------------------


// Begin ---------------------  Light Size -------------------------------------
#define LIGHT_SIZE0	0.5
#define LIGHT_SIZE1 0.5
#define LIGHT_SIZE2 0.5
#define LIGHT_SIZE3 0.5
#define LIGHT_SIZE {LIGHT_SIZE0,LIGHT_SIZE1,LIGHT_SIZE2,LIGHT_SIZE3};
// End  ----------------------  Light Size -------------------------------------

// Begin ---------------------  Light Color ------------------------------------
#define LIGHT_COLOR0	D3DXVECTOR4(1.0,1.0,1.0,1)
#define LIGHT_COLOR1	D3DXVECTOR4(0.0,0.0,0.0,1)
#define LIGHT_COLOR2	D3DXVECTOR4(0.0,0.0,0.0,1)
#define LIGHT_COLOR3	D3DXVECTOR4(0.1,0,0,1)
#define LIGHT_COLOR	{LIGHT_COLOR0,LIGHT_COLOR1,LIGHT_COLOR2,LIGHT_COLOR3}
// End   ---------------------  Light Color ------------------------------------

#define LIGHT_ZN		1
#define LIGHT_ZF_DELTA		100//zn is under control of user, this is only an incremental from Zn


#endif