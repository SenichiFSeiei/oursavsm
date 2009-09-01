#ifndef LIGHT_SETTINGS

#define NUM_LIGHT 8

// Begin ---------------------	Light Position ---------------------------------
#define LIGHT_POS0	D3DXVECTOR3(0.089104, 20.029869, -50.556995)//front
#define LIGHT_POS1	D3DXVECTOR3(45.089104, 50.029869, -30.556995)//left
#define LIGHT_POS2	D3DXVECTOR3(-50.089104, 20.029869, -45.556995)//right
#define LIGHT_POS3	D3DXVECTOR3(-50.089104, 20.029869, -25.556995)//front
#define LIGHT_POS4	D3DXVECTOR3(10.089104, 50.029869, 30.556995)//front
#define LIGHT_POS5	D3DXVECTOR3(0.089104, 50.029869, 40.556995)//left
#define LIGHT_POS6	D3DXVECTOR3(-50.089104, 50.029869, -10.556995)//right
#define LIGHT_POS7	D3DXVECTOR3(25.089104, 50.029869, 20.556995)//front
#define LIGHT_POS		{LIGHT_POS0,LIGHT_POS1,LIGHT_POS2,LIGHT_POS3,LIGHT_POS4,LIGHT_POS5,LIGHT_POS6,LIGHT_POS7};
// End ---------------------	Light Position ---------------------------------


// Begin ---------------------  Light Size -------------------------------------
#define LIGHT_SIZE0	0.8
#define LIGHT_SIZE1 0.1
#define LIGHT_SIZE2 0.2
#define LIGHT_SIZE3 0.2
#define LIGHT_SIZE4	0.5
#define LIGHT_SIZE5 1.5
#define LIGHT_SIZE6 0.5
#define LIGHT_SIZE7 0.2
#define LIGHT_SIZE {LIGHT_SIZE0,LIGHT_SIZE1,LIGHT_SIZE2,LIGHT_SIZE3,LIGHT_SIZE4,LIGHT_SIZE5,LIGHT_SIZE6,LIGHT_SIZE7};
// End  ----------------------  Light Size -------------------------------------

// Begin ---------------------  Light Color ------------------------------------
#define LIGHT_COLOR0	D3DXVECTOR4(3,3,3,1)
#define LIGHT_COLOR1	D3DXVECTOR4(1,1,1,1)
#define LIGHT_COLOR2	D3DXVECTOR4(2,2,2,1)
#define LIGHT_COLOR3	D3DXVECTOR4(2,2,2,1)
#define LIGHT_COLOR4	D3DXVECTOR4(0.4,0.4,0,1)
#define LIGHT_COLOR5	D3DXVECTOR4(1,1,1,1)
#define LIGHT_COLOR6	D3DXVECTOR4(0.4,0.4,0,1)
#define LIGHT_COLOR7	D3DXVECTOR4(1,1,1,1)
#define LIGHT_COLOR	{LIGHT_COLOR0,LIGHT_COLOR1,LIGHT_COLOR2,LIGHT_COLOR3,LIGHT_COLOR4,LIGHT_COLOR5,LIGHT_COLOR6,LIGHT_COLOR7}
// End   ---------------------  Light Color ------------------------------------

#define LIGHT_ZN0		20
#define LIGHT_ZN1		20
#define LIGHT_ZN2		20
#define LIGHT_ZN3		20
#define LIGHT_ZN4		10
#define LIGHT_ZN5		20
#define LIGHT_ZN6		10
#define LIGHT_ZN7		20
#define LIGHT_ZNS {LIGHT_ZN0,LIGHT_ZN1,LIGHT_ZN2,LIGHT_ZN3,LIGHT_ZN4,LIGHT_ZN5,LIGHT_ZN6,LIGHT_ZN7}

#define LIGHT_ZF_DELTA		200//zn is under control of user, this is only an incremental from Zn

#define LIGHT_VIEW_ANGLE0 D3DX_PI*4/5
#define LIGHT_VIEW_ANGLE1 D3DX_PI/3
#define LIGHT_VIEW_ANGLE2 D3DX_PI/2
#define LIGHT_VIEW_ANGLE3 D3DX_PI/2
#define LIGHT_VIEW_ANGLE4 D3DX_PI/2
#define LIGHT_VIEW_ANGLE5 D3DX_PI*4/5
#define LIGHT_VIEW_ANGLE6 D3DX_PI/2
#define LIGHT_VIEW_ANGLE7 D3DX_PI/3
#define LIGHT_VIEW_ANGLES {LIGHT_VIEW_ANGLE0,LIGHT_VIEW_ANGLE1,LIGHT_VIEW_ANGLE2,LIGHT_VIEW_ANGLE3,LIGHT_VIEW_ANGLE4,LIGHT_VIEW_ANGLE5,LIGHT_VIEW_ANGLE6,LIGHT_VIEW_ANGLE7}

#endif

//(1.0,1.0,0.0,1)
//(1.0,1.0,1,1)
//(1.0,1.0,1,1)
//(1.0,1.0,0.0,1)
//(1.0,0.0,0.0,1)
//(1.0,0.0,0,1)
//(1.0,1.0,1,1)
//(1.0,1.0,0.0,1)
