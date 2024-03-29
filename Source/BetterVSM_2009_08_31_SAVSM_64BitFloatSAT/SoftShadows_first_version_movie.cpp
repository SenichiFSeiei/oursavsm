//
// demonstrates use of SSMap class.
//

#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>
#include <sdkmisc.h>

#include <nvutcamera.h>
#include <nvutmesh.h>
#include "SoftShadowMap.h"
#include "SilhouetteBackprojection.h"
#include "HierarchalEdgeExtraction.h"
#include "SilhouetteBackprojectionNoSample.h"
#include "MarchingSilhouetteBP.h"
#include "HierBP.h"
#include "RenderFinal.h"
#include "BPGI.h"
#include "NoShadow.h"
#include "CommonDef.h"
#include "OGRE.h"
#include "HDRCubeTexture.h"
#include <NVUTSkybox.h>

#define MAX_WCHAR_SIZE      260

static NVUTCamera g_Camera;

//light management
static NVUTCamera g_LCamera[NUM_LIGHT];

static CD3DSettingsDlg g_D3DSettingsDlg;
static CDXUTDialogResourceManager g_DialogResourceManager;
static CDXUTDialog g_HUD;
static NVUTMesh g_MeshScene;
static NVUTMesh g_MeshLight;
static ID3DX10Font* g_pFont10 = NULL;
static ID3DX10Sprite* g_pSprite10 = NULL;
static CDXUTDialog g_SampleUI;
static ID3D10InputLayout *g_pMaxLayout = NULL;
static D3DXVECTOR3 g_vLightDir;
static ID3D10RasterizerState *g_pRenderState = NULL;
//parameter
static SSMap ssmap;
static bool g_bShowUI = true;
static bool g_bMoveCamera = true;
static float g_fFilterSizeCtrl = 0.1;
static float g_fFilterSize = 0.1;
static SilhouetteBP g_ABP;
static HierarchalEdgeExtraction g_HEEBP;
static SilhouetteBP_NOSMP g_ABP_nosmp;
static MarchSilhouetteBP g_MBP;
static HierBP g_HBP;
static BPGlobalIllumination   g_BPGI;
static NoShadow g_NoShadow;
static RenderFinal g_Final;
static int ShadowAlgorithm = SINGLE_LIGHT;
static float g_fDepthBiasDefault = 0.1;
static float g_fLightZn = 40;
static int g_nNumLightSample = 0;
static bool g_LightVary = false;
static bool g_CameraMove = false;
static bool g_LightMove = false;

HDRCubeTexture*               g_pEnvMap       = NULL; 
NVUTSkybox*                   g_pSkyBox       = NULL;
DXGI_SURFACE_DESC             g_pFloatBufferSurfaceDesc;
#define MAX_PATH_STR                       512
WCHAR  g_EnvMapFilePath[MAX_PATH_STR]; 
WCHAR* g_DefaultEnvMapName[]={ DEFAULT_HDR_ENVMAP }; 

static 	float g_fDefaultDepthBias			= 0.00125;
static 	float g_fDepthBiasHammer			= 0.02325;
static 	float g_fDepthBiasLeftForearm		= 0.0055;
static 	float g_fDepthBiasRightForearm		= 0.00745;
static 	float g_fDepthBiasLeftShoulder		= 0.003745;
static 	float g_fDepthBiasRightShoulder		= 0.00175;
static 	float g_fDepthBiasBlackPlate		= 0.0005;
static 	float g_fDepthBiasHelmet			= 0.00425;
static 	float g_fDepthBiasEyes				= 0.02475;
static 	float g_fDepthBiasBelt				= 0.0005;
static	float g_fDepthBiasLeftThigh			= 0.017;
static	float g_fDepthBiasRightThigh		= 0.00525;
static	float g_fDepthBiasLeftShin			= 0.0015;
static	float g_fDepthBiasRightShin			= 0.001;
static  float g_fDepthBiasObject0			= 0.00225;

//light management
static RenderObject *g_pLightLumiBuffer[NUM_LIGHT];
static RenderObject *g_pPingpongBuffer[2];

//----------------------------------------------------------

//--------------------------------------------------------------------------------------
// Forward declarations 
//--------------------------------------------------------------------------------------
bool CALLBACK ModifyDeviceSettings( DXUTDeviceSettings* pDeviceSettings, void* pUserContext );
void CALLBACK OnFrameMove( double fTime, float fElapsedTime, void* pUserContext );
LRESULT CALLBACK MsgProc( HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam, bool* pbNoFurtherProcessing, void* pUserContext );
void CALLBACK OnKeyboard( UINT nChar, bool bKeyDown, bool bAltDown, void* pUserContext );
void CALLBACK OnGUIEvent( UINT nEvent, int nControlID, CDXUTControl* pControl, void* pUserContext );

bool CALLBACK IsD3D10DeviceAcceptable( UINT Adapter, UINT Output, D3D10_DRIVER_TYPE DeviceType, DXGI_FORMAT BackBufferFormat, bool bWindowed, void* pUserContext );
HRESULT CALLBACK OnD3D10CreateDevice( ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
HRESULT CALLBACK OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
void CALLBACK OnD3D10FrameRender( ID3D10Device* pDev10, double fTime, float fElapsedTime, void* pUserContext );
void CALLBACK OnD3D10SwapChainReleasing( void* pUserContext );
void CALLBACK OnD3D10DestroyDevice( void* pUserContext );

//--------------------------------------------------------------------------------------
// Load new model
//--------------------------------------------------------------------------------------
static void LoadNewModel(bool bNeedUI = false)
{
    //HRESULT hr;              
    static WCHAR g_wcCleanFileName[MAX_WCHAR_SIZE];
    memcpy(g_wcCleanFileName, SCENE_SOURCE, sizeof(SCENE_SOURCE));

    BOOL bResult = TRUE;
    if( bResult )
    {
        g_MeshScene.Destroy();
        // setup the camera view parameters
        static const D3D10_INPUT_ELEMENT_DESC mesh_layout[] =
        {
            { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },
            { "NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D10_INPUT_PER_VERTEX_DATA, 0 },
            { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D10_INPUT_PER_VERTEX_DATA, 0 },
        };
        //if (g_MeshScene.Create(DXUTGetD3D10Device(), g_wcCleanFileName, (D3D10_INPUT_ELEMENT_DESC*)mesh_layout, 3) != S_OK)
		UINT scene_file_num = 1;
		LPCTSTR	pSceneFileNames[1] = {
			//L"4Columns.x",
			L"sponza\\sponza.x",
		};

		static WCHAR FAN_Mesh0[MAX_PATH] = L"MotionBlur\\windmillstage.sdkmesh";
		static WCHAR FAN_Mesh1[MAX_PATH] = L"MotionBlur\\Fan.sdkmesh";

		if( g_MeshScene.Create( MESH_SOURCE,//Animation mesh source
								ANIM_SOURCE,
								DXUTGetD3D10Device(),
								(D3D10_INPUT_ELEMENT_DESC*)suitlayout,
								(D3D10_INPUT_ELEMENT_DESC*)bodylayout,
								g_wcCleanFileName,
								pSceneFileNames,
								scene_file_num,
								(D3D10_INPUT_ELEMENT_DESC*)mesh_layout,
								3,
								FAN_Mesh0,
								FAN_Mesh1,
								true)
		   )

        {
            MessageBox(DXUTGetHWND(), L"Could not load geometry from sunclock.x", L"Error", MB_OK);
            exit(0);
        }
        D3DXVECTOR3 vLight[NUM_LIGHT]		= LIGHT_POS;
        D3DXVECTOR3 vEye		= EYE_POS;
        D3DXVECTOR3 vLookAt		= LOOK_AT_POS;

		//light management
		for( int light_idx = 0; light_idx < NUM_LIGHT; ++light_idx )
		{
			g_LCamera[light_idx].SetViewParams(&vLight[light_idx], &vLookAt);
		}

        g_Camera.SetViewParams(&vEye, &vLookAt);

    }
}
static void InitApp()
{
    g_D3DSettingsDlg.Init( &g_DialogResourceManager );
    g_HUD.Init( &g_DialogResourceManager );
    g_SampleUI.Init( &g_DialogResourceManager );

    g_HUD.SetCallback( OnGUIEvent ); int iY = 10; 
    g_HUD.AddButton( IDC_CHANGEDEVICE, L"Change device (F2)", 35, iY, 125, 22, VK_F2 );

    g_SampleUI.EnableKeyboardInput( true );
    g_SampleUI.SetCallback( OnGUIEvent );
    iY = 10;
    g_SampleUI.AddStatic( IDC_SHADOW_ALGORITHM_LABEL, L"Shadow algorithm:", 35, iY, 125, 22 );
    CDXUTComboBox *pComboBox;
    g_SampleUI.AddComboBox( IDC_SHADOW_ALGORITHM, 35, iY += 20, 125, 30, 0, false, &pComboBox);
    pComboBox->AddItem(L"StandardBP", NULL);
    pComboBox->AddItem(L"BP_NoSMP", NULL);
    pComboBox->AddItem(L"MarchingBP", NULL);
    pComboBox->AddItem(L"HirEdgeExtraction", NULL);
    pComboBox->AddItem(L"HirBP", NULL);
    pComboBox->AddItem(L"BPGI", NULL);
    pComboBox->AddItem(L"NoShadows", NULL);
    pComboBox->AddItem(L"SingleLight", NULL);

    
	g_SampleUI.AddStatic( IDC_COMMON_LABEL, L"Light Zn", 35, iY += 25, 125, 22 );
    g_SampleUI.AddSlider( IDC_LIGHT_ZN, 160, iY, 124, 22, 0, 100, 40 );

	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"NumLightSample", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_NUM_LIGHT_SAMPLE, 160, iY, 124, 22, 0, 16, 0 );

	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDefaultDepthBias", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDefaultDepthBias, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasHammer", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasHammer, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasLeftForearm", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasLeftForearm, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasRightForearm", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasRightForearm, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasLeftShoulder", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasLeftShoulder, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasRightShoulder", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasRightShoulder, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasBlackPlate", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasBlackPlate, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasHelmet", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasHelmet, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasEyes", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasEyes, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasBelt", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasBelt, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasLeftThigh", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasLeftThigh, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasRightThigh", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasRightThigh, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasLeftShin", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasLeftShin, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasRightShin", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasRightShin, 160, iY, 124, 22, 0, 100, 40 );
	
	g_SampleUI.AddStatic(IDC_COMMON_LABEL, L"fDepthBiasObject0", 35, iY += 25, 125, 22 );
	g_SampleUI.AddSlider(IDC_fDepthBiasObject0, 160, iY, 124, 22, 0, 100, 40 );

    g_SampleUI.AddCheckBox( IDC_BTEXTURED, L"Enable Texturing", 35, iY += 25, 124, 22, true);
    g_SampleUI.AddCheckBox( IDC_BMOVECAMERA, L"Move Camera", 35, iY += 25, 124, 22, true);
    g_SampleUI.AddCheckBox( IDC_BDUMP_SHADOWMAP, L"Dump Shadow Map", 35, iY += 25, 124, 22, false);
    g_SampleUI.AddCheckBox( IDC_STATIC, L"Freeze Model", 35, iY += 25, 124, 22, true);
    g_SampleUI.AddCheckBox( IDC_ANIMATE, L"Show Animated Model", 35, iY += 25, 124, 22, true);
    g_SampleUI.AddCheckBox( IDC_SCENE, L"Show scene", 35, iY += 25, 124, 22, true);
	g_SampleUI.AddCheckBox( IDC_FAN, L"Show Fan", 35, iY += 25, 124, 22, true);
	g_SampleUI.AddCheckBox( IDC_FRAME_DUMP, L"Show Fan", 35, iY += 25, 124, 22, false);

    g_SampleUI.AddStatic( IDC_LIGHT_SIZE_LABEL, L"Light source size:", 35, iY += 25, 125, 22 );
    g_SampleUI.AddSlider( IDC_LIGHT_SIZE, 160, iY, 124, 22, 0, 100, 0 );


	g_pSkyBox    = new NVUTSkybox();
    g_pEnvMap    = new HDRCubeTexture;


}
static void RenderText()
{
    CDXUTTextHelper txtHelper( g_pFont10, g_pSprite10, 15 );
    txtHelper.Begin();
    txtHelper.SetInsertionPos( 5, 5 );
    txtHelper.SetForegroundColor( D3DXCOLOR( 1.0f, 0.0f, 0.0f, 1.0f ) );
    txtHelper.DrawTextLine( DXUTGetFrameStats(true) );
    txtHelper.DrawTextLine( DXUTGetDeviceStats() );
    txtHelper.End();
}

HRESULT CreatePipeBuffer(ID3D10Device* pDev10, UINT uiNumSpawnPoints, UINT uiMaxFaces);
HRESULT CreateRandomTexture(ID3D10Device* pDev10);
HRESULT GenerateTriCenterBuffer( ID3D10Device* pDev10, LPCTSTR szMesh, UINT *puNumFaces );
HRESULT LoadTextureArray( ID3D10Device* pDev10, LPCTSTR* szTextureNames, int iNumTextures, ID3D10Texture2D** ppTex2D, ID3D10ShaderResourceView** ppSRV);

//--------------------------------------------------------------------------------------
// Entry point to the program. Initializes everything and goes into a message processing 
// loop. Idle time is used to render the scene.
//--------------------------------------------------------------------------------------
int WINAPI wWinMain( HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow )
{
    // Enable run-time memory check for debug builds.
#if defined(DEBUG) | defined(_DEBUG)
    _CrtSetDbgFlag( _CRTDBG_ALLOC_MEM_DF | _CRTDBG_LEAK_CHECK_DF );
#endif

    // DXUT will create and use the best device (either D3D9 or D3D10) 
    // that is available on the system depending on which D3D callbacks are set below

    // Set DXUT callbacks
    DXUTSetCallbackDeviceChanging( ModifyDeviceSettings );
    DXUTSetCallbackMsgProc( MsgProc );
    DXUTSetCallbackKeyboard( OnKeyboard );
    DXUTSetCallbackFrameMove( OnFrameMove );
    DXUTSetCallbackD3D10DeviceAcceptable( IsD3D10DeviceAcceptable );
    DXUTSetCallbackD3D10DeviceCreated( OnD3D10CreateDevice );
    DXUTSetCallbackD3D10SwapChainResized( OnD3D10SwapChainResized );
    DXUTSetCallbackD3D10FrameRender( OnD3D10FrameRender );
    DXUTSetCallbackD3D10SwapChainReleasing( OnD3D10SwapChainReleasing );
    DXUTSetCallbackD3D10DeviceDestroyed( OnD3D10DestroyDevice );

    HRESULT hr;
    V_RETURN(DXUTSetMediaSearchPath(L"..\\Source\\SoftShadows"));

    InitApp();

    DXUTInit( true, true, NULL ); // Parse the command line, show msgboxes on error, no extra command line params
    DXUTSetCursorSettings( true, true ); // Show the cursor and clip it when in full screen
    DXUTCreateWindow( L"SoftShadows" );
    DXUTCreateDevice( true, 1024, 768 );
    DXUTMainLoop(); // Enter into the DXUT render loop

    return DXUTGetExitCode();
}
//--------------------------------------------------------------------------------------
// Called right before creating a D3D9 or D3D10 device, allowing the app to modify the device settings as needed
//--------------------------------------------------------------------------------------
bool CALLBACK ModifyDeviceSettings( DXUTDeviceSettings* pDeviceSettings, void* pUserContext )
{
    // For the first device created if its a REF device, optionally display a warning dialog box
    static bool s_bFirstTime = true;
	pDeviceSettings->d3d10.sd.SampleDesc.Count = 1;
	pDeviceSettings->d3d10.sd.SampleDesc.Quality = 0;
    if( s_bFirstTime )
    {
        s_bFirstTime = false;
        if((DXUT_D3D9_DEVICE == pDeviceSettings->ver && pDeviceSettings->d3d9.DeviceType == D3DDEVTYPE_REF) ||
            (DXUT_D3D10_DEVICE == pDeviceSettings->ver && pDeviceSettings->d3d10.DriverType == D3D10_DRIVER_TYPE_REFERENCE))
            DXUTDisplaySwitchingToREFWarning( pDeviceSettings->ver );
    }

    return true;
}
//--------------------------------------------------------------------------------------
// Handle updates to the scene.  This is called regardless of which D3D API is used
//--------------------------------------------------------------------------------------
void CALLBACK OnFrameMove( double fTime, float fElapsedTime, void* pUserContext )
{
    // update the camera's position based on user input 
    g_Camera.FrameMove(fElapsedTime);

	//light management
	for( int light_idx = 0; light_idx < 1/*NUM_LIGHT*/; ++light_idx )//FIX A LIGHT FOR CONSTANT ILLUMINATION
	{
		g_LCamera[light_idx].FrameMove(fElapsedTime);
	}
}
//--------------------------------------------------------------------------------------
// Handle messages to the application
//--------------------------------------------------------------------------------------
LRESULT CALLBACK MsgProc( HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam, bool* pbNoFurtherProcessing, void* pUserContext )
{
    // Pass messages to dialog resource manager calls so GUI state is updated correctly
    *pbNoFurtherProcessing = g_DialogResourceManager.MsgProc( hWnd, uMsg, wParam, lParam );
    if( *pbNoFurtherProcessing )
        return 0;

    // Pass messages to settings dialog if its active
    if( g_D3DSettingsDlg.IsActive() )
    {
        g_D3DSettingsDlg.MsgProc( hWnd, uMsg, wParam, lParam );
        return 0;
    }

    // Give the dialogs a chance to handle the message first
    *pbNoFurtherProcessing = g_HUD.MsgProc( hWnd, uMsg, wParam, lParam );
    if( *pbNoFurtherProcessing )
        return 0;
    *pbNoFurtherProcessing = g_SampleUI.MsgProc( hWnd, uMsg, wParam, lParam );
    if( *pbNoFurtherProcessing )
        return 0;

    // Pass all remaining windows messages to camera so it can respond to user input
    unsigned iTmp = g_SampleUI.GetCheckBox(IDC_BMOVECAMERA)->GetChecked();

    if ( iTmp ) // left button pressed
    { 
		g_Camera.HandleMessages( hWnd, uMsg, wParam, lParam ); 
	}
	else{
		//light management
		for( int light_idx = 0; light_idx < NUM_LIGHT; ++ light_idx )
		{
			g_LCamera[light_idx].HandleMessages( hWnd, uMsg, wParam, lParam );
		}
	}

    return 0;
}
//--------------------------------------------------------------------------------------
// Handle key presses
//--------------------------------------------------------------------------------------
void CALLBACK OnKeyboard(UINT nChar, bool bKeyDown, bool bAltDown, void* pUserContext)
{
    if( !bKeyDown )	return;
    switch( nChar )
    {
    case VK_F1:
        g_bShowUI = !g_bShowUI;
        break;
	case VK_F7:
		g_LightVary = !g_LightVary;
		break;
	case VK_F8:
		g_CameraMove = !g_CameraMove;
		break;
	case VK_F9:
		g_LightMove = !g_LightMove;
		break;
    }
}
//--------------------------------------------------------------------------------------
// Handles the GUI events
//--------------------------------------------------------------------------------------
void CALLBACK OnGUIEvent(UINT nEvent, int nControlID, CDXUTControl* pControl, void* pUserContext)
{
    switch( nControlID )
    {
    case IDC_CHANGEDEVICE:
        g_D3DSettingsDlg.SetActive( !g_D3DSettingsDlg.IsActive() );
        break;
    case IDC_LIGHT_SIZE:
        g_fFilterSizeCtrl = (float)g_SampleUI.GetSlider(IDC_LIGHT_SIZE)->GetValue() / 100.0;
        break;
    case IDC_SHADOW_ALGORITHM:
		ShadowAlgorithm = ((CDXUTComboBox*)pControl)->GetSelectedIndex();
        break;
	case IDC_LIGHT_ZN:
		g_fLightZn = 2*(float)g_SampleUI.GetSlider(IDC_LIGHT_ZN)->GetValue();
		break;
	case IDC_fDefaultDepthBias:
		g_fDefaultDepthBias = (float)g_SampleUI.GetSlider(IDC_fDefaultDepthBias)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasHammer:
		g_fDepthBiasHammer = (float)g_SampleUI.GetSlider(IDC_fDepthBiasHammer)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasLeftForearm:
		g_fDepthBiasLeftForearm = (float)g_SampleUI.GetSlider(IDC_fDepthBiasLeftForearm)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasRightForearm:
		g_fDepthBiasRightForearm = (float)g_SampleUI.GetSlider(IDC_fDepthBiasRightForearm)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasLeftShoulder:
		g_fDepthBiasLeftShoulder = (float)g_SampleUI.GetSlider(IDC_fDepthBiasLeftShoulder)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasRightShoulder:
		g_fDepthBiasRightShoulder = (float)g_SampleUI.GetSlider(IDC_fDepthBiasRightShoulder)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasBlackPlate:
		g_fDepthBiasBlackPlate = (float)g_SampleUI.GetSlider(IDC_fDepthBiasBlackPlate)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasHelmet:
		g_fDepthBiasHelmet = (float)g_SampleUI.GetSlider(IDC_fDepthBiasHelmet)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasEyes:
		g_fDepthBiasEyes = (float)g_SampleUI.GetSlider(IDC_fDepthBiasEyes)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasBelt:
		g_fDepthBiasBelt = (float)g_SampleUI.GetSlider(IDC_fDepthBiasBelt)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasLeftThigh:
		g_fDepthBiasLeftThigh = (float)g_SampleUI.GetSlider(IDC_fDepthBiasLeftThigh)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasRightThigh:
		g_fDepthBiasRightThigh = (float)g_SampleUI.GetSlider(IDC_fDepthBiasRightThigh)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasLeftShin:
		g_fDepthBiasLeftShin = (float)g_SampleUI.GetSlider(IDC_fDepthBiasLeftShin)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasRightShin:
		g_fDepthBiasRightShin = (float)g_SampleUI.GetSlider(IDC_fDepthBiasRightShin)->GetValue()/4000.0;
		break;
	case IDC_fDepthBiasObject0:
		g_fDepthBiasObject0 = (float)g_SampleUI.GetSlider(IDC_fDepthBiasObject0)->GetValue()/4000.0;
		break;
	case IDC_NUM_LIGHT_SAMPLE:
		g_nNumLightSample = 2*(int)g_SampleUI.GetSlider(IDC_NUM_LIGHT_SAMPLE)->GetValue();
		break;
    }    
}
//--------------------------------------------------------------------------------------
// Reject any D3D10 devices that aren't acceptable by returning false
//--------------------------------------------------------------------------------------
bool CALLBACK IsD3D10DeviceAcceptable(UINT Adapter, UINT Output, D3D10_DRIVER_TYPE DeviceType, DXGI_FORMAT BackBufferFormat, bool bWindowed, void* pUserContext)
{
    return true;
}
//--------------------------------------------------------------------------------------
// Create any D3D10 resources that aren't dependant on the back buffer
//--------------------------------------------------------------------------------------
HRESULT CALLBACK OnD3D10CreateDevice(ID3D10Device* pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void* pUserContext)
{
    HRESULT hr;

    V_RETURN(DXUTSetMediaSearchPath(L"..\\Source\\SoftShadows"));
    V_RETURN(g_DialogResourceManager.OnD3D10CreateDevice(pDev10));
    V_RETURN(g_D3DSettingsDlg.OnD3D10CreateDevice(pDev10));
    V_RETURN(D3DX10CreateFont(pDev10, 15, 0, FW_BOLD, 1, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, DEFAULT_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Arial", &g_pFont10));

    g_SampleUI.GetSlider(IDC_LIGHT_SIZE)->SetValue((int)(g_fFilterSize * 200.0));
	g_SampleUI.GetComboBox(IDC_SHADOW_ALGORITHM)->SetSelectedByIndex(ssmap.bAccurateShadow == true ? 0 : 1);
    V_RETURN(D3DX10CreateSprite(pDev10, 512, &g_pSprite10));

    LoadNewModel();

	V_RETURN( DXUTFindDXSDKMediaFileCch( g_EnvMapFilePath, MAX_PATH_STR, g_DefaultEnvMapName[0] ) );
    g_pEnvMap->OnCreateDevice(pDev10, g_EnvMapFilePath, DXGI_FORMAT_R8G8B8A8_UNORM);
    g_pSkyBox->OnCreateDevice( pDev10 );
    g_pSkyBox->SetTexture( g_pEnvMap->m_TextureRV );
	g_pFloatBufferSurfaceDesc.SampleDesc.Count   = pBackBufferSurfaceDesc->SampleDesc.Count;
    g_pFloatBufferSurfaceDesc.SampleDesc.Quality = pBackBufferSurfaceDesc->SampleDesc.Quality;


	ssmap.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);

    D3DXVECTOR3 vTmp = D3DXVECTOR3(1, 2, 3);
    D3DXVec3Normalize(&g_vLightDir, &vTmp);

    SAFE_RELEASE(g_pRenderState);
    D3D10_RASTERIZER_DESC RasterizerState;
    RasterizerState.FillMode = D3D10_FILL_SOLID;
    RasterizerState.CullMode = D3D10_CULL_FRONT;
    RasterizerState.FrontCounterClockwise = true;
    RasterizerState.DepthBias = false;
    RasterizerState.DepthBiasClamp = 0;
    RasterizerState.SlopeScaledDepthBias = 0;
    RasterizerState.DepthClipEnable = true;
    RasterizerState.ScissorEnable = false;
    RasterizerState.MultisampleEnable = false;
    RasterizerState.AntialiasedLineEnable = false;
    V(pDev10->CreateRasterizerState(&RasterizerState, &g_pRenderState));

	g_ABP.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);
	g_NoShadow.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);
	g_BPGI.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);
	g_HBP.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);
	g_ABP_nosmp.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);
	g_MBP.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);
	g_HEEBP.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);
	g_Final.OnD3D10CreateDevice(pDev10,pBackBufferSurfaceDesc,pUserContext);

	{//must be after g_ABP create a device,because they uses the members of g_ABP
		static const D3D10_INPUT_ELEMENT_DESC mesh_layout[] =
		{
			{ "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },
			{ "NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D10_INPUT_PER_VERTEX_DATA, 0 },
			{ "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D10_INPUT_PER_VERTEX_DATA, 0 },
		};
		if (g_MeshLight.Create(pDev10, L"arrow.x", (D3D10_INPUT_ELEMENT_DESC*)mesh_layout, 3) != S_OK)
		{
			MessageBox(DXUTGetHWND(), L"Could not load geometry from arrow.x", L"Error", MB_OK);
			exit(0);
		}
		D3D10_PASS_DESC PassDesc;
		V_RETURN(g_ABP.m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_TECH)->GetPassByIndex(0)->GetDesc(&PassDesc));
		V_RETURN(pDev10->CreateInputLayout(mesh_layout, 3, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &g_pMaxLayout));
	}

//light management
	for( int light_idx = 0; light_idx < NUM_LIGHT; ++light_idx )
	{
		g_pLightLumiBuffer[light_idx] = new RenderObject( "RenderScreenPixelPos" );
		g_pLightLumiBuffer[light_idx] ->OnD3D10CreateDevice( NULL,pDev10, pBackBufferSurfaceDesc, pUserContext);
	}

	for( int p_idx = 0 ; p_idx < 2 ; ++p_idx )
	{
		g_pPingpongBuffer[p_idx] = new RenderObject( "RenderScreenPixelPos" );
		g_pPingpongBuffer[p_idx] ->OnD3D10CreateDevice( NULL,pDev10, pBackBufferSurfaceDesc, pUserContext);
	}
//--------------------------------------------------------------------------------------------------------

    return S_OK;
}
//--------------------------------------------------------------------------------------
// Create any D3D10 resources that depend on the back buffer
//--------------------------------------------------------------------------------------
HRESULT CALLBACK OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
    HRESULT hr = S_OK;

    V_RETURN(g_DialogResourceManager.OnD3D10ResizedSwapChain(pDev10, pBackBufferSurfaceDesc));

    // setup the camera projection parameters
    g_Camera.SetWindow(pBackBufferSurfaceDesc->Width, pBackBufferSurfaceDesc->Height);

	//light management
	for( int light_idx = 0; light_idx < NUM_LIGHT; ++light_idx )
	{
		g_LCamera[light_idx].SetWindow(pBackBufferSurfaceDesc->Width, pBackBufferSurfaceDesc->Height);
	}

    g_HUD.SetLocation(pBackBufferSurfaceDesc->Width-170, 0);
    g_HUD.SetSize(170, 170);

    g_SampleUI.SetLocation( pBackBufferSurfaceDesc->Width-300, pBackBufferSurfaceDesc->Height-700 );
    g_SampleUI.SetSize( 170, 300 );

	g_ABP.OnD3D10SwapChainResized(pDev10,pSwapChain,pBackBufferSurfaceDesc,pUserContext );
	g_NoShadow.OnD3D10SwapChainResized(pDev10,pSwapChain,pBackBufferSurfaceDesc,pUserContext );
	g_BPGI.OnD3D10SwapChainResized(pDev10,pSwapChain,pBackBufferSurfaceDesc,pUserContext );
	g_Final.OnD3D10SwapChainResized(pDev10,pSwapChain,pBackBufferSurfaceDesc,pUserContext );
	g_HBP.OnD3D10SwapChainResized(pDev10,pSwapChain,pBackBufferSurfaceDesc,pUserContext );
	g_HEEBP.OnD3D10SwapChainResized(pDev10,pSwapChain,pBackBufferSurfaceDesc,pUserContext );
	g_MBP.OnD3D10SwapChainResized(pDev10,pSwapChain,pBackBufferSurfaceDesc,pUserContext );

	//light management
	D3D10_TEXTURE2D_DESC rtDesc_scrpos =
	{
		pBackBufferSurfaceDesc->Width, //UINT Width;
		pBackBufferSurfaceDesc->Height, //UINT Height;
		1,//UINT MipLevels;
		1,//UINT ArraySize;
		DXGI_FORMAT_R16G16B16A16_FLOAT,//DXGI_FORMAT Format;
		{1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
		D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;

		D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET ,//UINT BindFlags;
		0,//UINT CPUAccessFlags;
		0,//UINT MiscFlags;
	};

	for( int light_idx = 0; light_idx < NUM_LIGHT; ++light_idx )
	{
		g_pLightLumiBuffer[light_idx]->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	}
	for( int p_idx = 0 ; p_idx < 2 ; ++p_idx )
	{
		g_pPingpongBuffer[p_idx]->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	}

	//---------------------------------------

    g_pSkyBox->OnResizedSwapChain   ( pDev10, &g_pFloatBufferSurfaceDesc );
	g_pFloatBufferSurfaceDesc.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
	g_pFloatBufferSurfaceDesc.Height = pBackBufferSurfaceDesc->Height;
	g_pFloatBufferSurfaceDesc.Width  = pBackBufferSurfaceDesc->Width;


    return hr;
}
//--------------------------------------------------------------------------------------
void CALLBACK OnD3D10FrameRender(ID3D10Device* pDev10, double fTime, float fElapsedTime, void* pUserContext)
{


    HRESULT hr;

	D3DXVECTOR3 vEye = *g_Camera.GetEyePt();
	float x_incre = 0.1;
	static float total_x_incre = 0;
	float z_incre = 0.1;
	static float total_z_incre = 0;
	float y_incre = 0.15;
	static float total_y_incre = 0;
	static float move_dir = 0;
	static float animation_timer = 0;
	if( g_CameraMove )
	{
		if( move_dir == 0 )
		{
			vEye.y -= y_incre * 10;
			vEye.x -= x_incre*0.35*1.5*10;
			D3DXVECTOR3 vLookAt = *g_Camera.GetLookAtPt();
			g_Camera.SetViewParams(&vEye, &vLookAt);
			total_y_incre += y_incre * 10;
			if( total_y_incre >52)
			{
				move_dir = 0.5;
			}
		}
		if( move_dir == 0.5 )
		{

			animation_timer += 0.5;
			if( animation_timer > 48 )
			{
				move_dir = 1;
				animation_timer = 0;
			}
		}

		if( move_dir == 1 )
		{

			animation_timer += 0.1;
			if( animation_timer > 25 )
			{
				move_dir = 2;
				animation_timer = 0;
			}
		}
		if( move_dir == 2 )
		{
			vEye.x += x_incre * 3;
			D3DXVECTOR3 vLookAt = *g_Camera.GetLookAtPt();
			g_Camera.SetViewParams(&vEye, &vLookAt);
			total_x_incre += x_incre * 3;
			if( total_x_incre > 20 )
			{
				move_dir = 3;
				total_x_incre = 0;
			}
		}
		if( move_dir == 3 )
		{
			vEye.z += z_incre * 3;
			vEye.y += y_incre* 1.5 * 1.5;
			D3DXVECTOR3 vLookAt = *g_Camera.GetLookAtPt();
			g_Camera.SetViewParams(&vEye, &vLookAt);
			total_z_incre += z_incre * 3;
			if( total_z_incre > 25 )
			{
				move_dir = 4;
				total_z_incre = 0;
			}
		}
		if( move_dir == 4 )
		{
			vEye.x -= x_incre * 3;
			D3DXVECTOR3 vLookAt = *g_Camera.GetLookAtPt();
			g_Camera.SetViewParams(&vEye, &vLookAt);
			total_x_incre += x_incre * 3;
			if( total_x_incre > 20 )
			{
				move_dir = 5;
				total_x_incre = 0;
			}
		}
		if( move_dir == 5 )
		{
			vEye.z -= z_incre * 1.5;
			vEye.y -= y_incre*0.9*1.5 * 0.5;
			vEye.x -= x_incre * 0.1;
			D3DXVECTOR3 vLookAt = *g_Camera.GetLookAtPt();
			g_Camera.SetViewParams(&vEye, &vLookAt);
			total_z_incre += z_incre * 1.5;
			if( total_z_incre > 25 )
			{
				move_dir = 6;
				total_z_incre = 0;
			}
		}
		if( move_dir == 6 )
		{
			move_dir = 7;
			//vEye.x += x_incre;
			//D3DXVECTOR3 vLookAt = *g_Camera.GetLookAtPt();
			//g_Camera.SetViewParams(&vEye, &vLookAt);
			//total_x_incre += x_incre;
			//if( total_x_incre > 3 )
			//{
			//	move_dir = 7;
			//	total_x_incre = 0;
			//}

		}

		if( move_dir == 7 )
		{

			move_dir = 8;
		}

		if( move_dir == 8 )
		{

			animation_timer += 0.1;
			if( animation_timer > 200 )
			{
				move_dir = 8;
				animation_timer = 0;
			}
		}



	}

	if( move_dir == 7 || move_dir == 0.5)
		g_LightVary = true;
	else 
		g_LightVary = false;

	if( move_dir == 8 )
		g_LightMove = true;
	else 
		g_LightMove = false;


	static double old_fTime = 0.001;
	fTime = old_fTime;
	old_fTime += 0.05;
	static double oldTime = 0;
	static unsigned old_iSta = 0;
	static double stop_time = 0;
	static double total_stop_time = 0;
	double tmp = fTime;

	unsigned iSta = g_SampleUI.GetCheckBox(IDC_STATIC)->GetChecked();
	if( move_dir == 1 && animation_timer>2 ) 
		iSta = 0;
	else if( move_dir == 1 && animation_timer>47.5 )
		iSta = 1;
	else if( move_dir == 2 )
		iSta = 1;

	if( 0 == old_iSta  && 1 == iSta )//turn to be static
	{
		stop_time = fTime - total_stop_time;
	}
	if( 1 == iSta )
	{
		total_stop_time += ( fTime - oldTime );
		fTime = stop_time;
	}
	if( 0 == iSta )
	{
		fTime -= total_stop_time;
	}
	old_iSta = iSta;
	oldTime = tmp;

	NVUTCamera& g_CameraRef = g_Camera;

	// compute view matrix
	D3DXMATRIX mTmp, mWorldView, mWorldViewProj, mWorldViewInv;
	D3DXMatrixInverse(&mTmp, NULL, g_CameraRef.GetWorldMatrix());
	D3DXMatrixMultiply(&mWorldView, &mTmp, g_CameraRef.GetViewMatrix());

	// correct near/far clip planes according to camera location
	const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc = DXUTGetDXGIBackBufferSurfaceDesc();
	D3DXVECTOR3 vBox[2];
	float fAspectRatio = pBackBufferSurfaceDesc->Width / (FLOAT)pBackBufferSurfaceDesc->Height;
	g_CameraRef.SetProjParams(D3DX_PI/3, fAspectRatio, 0.1, 500);

	// clear depth and color
	ID3D10DepthStencilView* pDSV = DXUTGetD3D10DepthStencilView();
	pDev10->ClearDepthStencilView( pDSV, D3D10_CLEAR_DEPTH, 1.0, 0);
	ID3D10RenderTargetView* pRTV = DXUTGetD3D10RenderTargetView();

	if( g_D3DSettingsDlg.IsActive() )
	{
		g_D3DSettingsDlg.OnRender( fElapsedTime );
		return;
	}


	Parameters para;
	para.fLightZn				=	g_fLightZn;				

	float biases[15];
	biases[0]	=	g_fDepthBiasObject0;
	biases[1]	=	g_fDefaultDepthBias;		
	biases[2]	=	g_fDepthBiasHammer;
	biases[3]	=	g_fDepthBiasLeftForearm;
	biases[4]	=	g_fDepthBiasRightForearm;
	biases[5]	=	g_fDepthBiasLeftShoulder;
	biases[6]	=	g_fDepthBiasRightShoulder;
	biases[7]	=	g_fDepthBiasBlackPlate;
	biases[8]	=	g_fDepthBiasHelmet;
	biases[9]	=	g_fDepthBiasEyes;
	biases[10]	=	g_fDepthBiasBelt;
	biases[11]	=	g_fDepthBiasLeftThigh;
	biases[12]	=	g_fDepthBiasRightThigh;
	biases[13]	=	g_fDepthBiasLeftShin;
	biases[14]	=	g_fDepthBiasRightShin;
	g_MeshScene.set_biases(biases,15);
	
	float light_size[NUM_LIGHT] = LIGHT_SIZE;
	float light_ZNS[NUM_LIGHT] = LIGHT_ZNS;
	float light_view_angle[NUM_LIGHT] = LIGHT_VIEW_ANGLES;

	D3DXVECTOR4 light_color[NUM_LIGHT] = LIGHT_COLOR;

	bool render_ogre = g_SampleUI.GetCheckBox( IDC_ANIMATE )->GetChecked();
	bool render_scene = g_SampleUI.GetCheckBox( IDC_SCENE )->GetChecked();
	bool render_fan = g_SampleUI.GetCheckBox( IDC_FAN )->GetChecked();

	float ClearColor[4] = { 0, 0, 0, 1 };
	for( int p_idx = 0 ; p_idx < 2 ; ++p_idx )
	{
		pDev10->ClearRenderTargetView(g_pPingpongBuffer[p_idx]->m_pRTView, ClearColor);
	}

	//light management
	ID3D10RenderTargetView *p_RTV;
	ID3D10ShaderResourceView *p_SRV;

    D3DXVECTOR3 vLookAt		= LOOK_AT_POS;

	static float light_scale_factor = 0.2;
	static float ls_incre = 0.01;
	
	if( g_LightVary == true || g_fFilterSize < g_fFilterSizeCtrl )
	{
		g_fFilterSize -= ls_incre;
		if( g_fFilterSize < 0.1 || g_fFilterSize > g_fFilterSizeCtrl )
			ls_incre = -ls_incre;
	}
	else
	{
		g_fFilterSize = g_fFilterSizeCtrl;
	}
	
// rendering a subdivided light
	float scaled_light_size = (g_fFilterSize*LIGHT_SCALE_FACTOR);
	float fStartPt = -scaled_light_size;
	float fInterval = 2 * scaled_light_size / g_nNumLightSample;
	float fSubLightSize = g_fFilterSize;
	if( g_nNumLightSample > 0 )
	{
		fSubLightSize = fSubLightSize / g_nNumLightSample;
	}
	if( g_nNumLightSample == 0 )
	{
		g_nNumLightSample = 1;
	}

	static float total_light_x_incre = 0;
	static int light_mov_dir = 0;
	float shadow_factor = 0.8/(g_nNumLightSample * g_nNumLightSample);
	for( int ix = 0; ix < g_nNumLightSample; ++ix )
	{
		for( int iy = 0; iy < g_nNumLightSample; ++iy )
		{
			D3DXVECTOR3 vLight = *g_LCamera[0].GetEyePt();
			float x_incre = 0.005;
			if( g_LightMove )
			{
				float range = 3.8;
				if( light_mov_dir == 0 )
				{
					vLight.x += x_incre;
					D3DXVECTOR3 vLookAt = *g_LCamera[0].GetLookAtPt();
					g_LCamera[0].SetViewParams(&vLight, &vLookAt);
					total_light_x_incre += x_incre;
					if( total_light_x_incre > range * 1.0 )
					{
						light_mov_dir = 1;
					}
				}
				else
				{
					vLight.x -= x_incre;
					D3DXVECTOR3 vLookAt = *g_LCamera[0].GetLookAtPt();
					g_LCamera[0].SetViewParams(&vLight, &vLookAt);
					total_light_x_incre -= x_incre;
					if( total_light_x_incre < -range * 2.0 )
					{
						light_mov_dir = 0;
					}
				}
			}
			NVUTCamera  local_cam = g_LCamera[0];

			D3DXVECTOR3 vTrans( fStartPt+(ix+0.5)*fInterval,fStartPt+(iy+0.5)*fInterval,0 );
			if( g_nNumLightSample == 1 )
			{
				vTrans = D3DXVECTOR3(0,0,0);
			}
			D3DXMATRIX mInvLightView;
			D3DXVECTOR4 tmp_light_pos;
			D3DXMatrixInverse(&mInvLightView, NULL, local_cam.GetViewMatrix());
			D3DXVec3Transform(&tmp_light_pos, &vTrans, &mInvLightView );
			D3DXVECTOR3 tmp_light_pos_3(tmp_light_pos.x,tmp_light_pos.y,tmp_light_pos.z);
			local_cam.SetViewParams( &tmp_light_pos_3, &vLookAt );
			
			g_MeshScene.set_parameters( render_ogre, render_scene, render_fan, false );
			NVUTCamera& g_LCameraRef = local_cam;
			g_fLightZn = light_ZNS[0];
			D3DXMATRIX mLightView;
			// here we compute light viewprojection so that light oversees the whole scene
			D3DXMATRIX mTranslate;

			D3DXMatrixInverse(&mTranslate, NULL, g_LCameraRef.GetWorldMatrix());
			D3DXMatrixMultiply(&mLightView, &mTranslate, g_LCameraRef.GetViewMatrix());
			g_LCameraRef.SetProjParams(light_view_angle[0], 1.0, g_fLightZn, g_fLightZn + LIGHT_ZF_DELTA);
	
			unsigned iTmp = g_SampleUI.GetCheckBox(IDC_BDUMP_SHADOWMAP)->GetChecked();
			ssmap.Render(pDev10, &g_MeshScene, g_LCameraRef,fTime,fElapsedTime,iTmp);
			
			pDev10->RSSetState(g_pRenderState);

			if( (ix * g_nNumLightSample + iy) % 2 == 0 )
			{
				p_RTV = g_pPingpongBuffer[0]->m_pRTView;
				p_SRV = g_pPingpongBuffer[1]->m_pSRView;
			}
			else
			{
				p_RTV = g_pPingpongBuffer[1]->m_pRTView;
				p_SRV = g_pPingpongBuffer[0]->m_pSRView;
			}
			
			V(g_BPGI.m_pEffect->GetVariableByName("g_fLumiFactor")->AsScalar()->SetFloat( shadow_factor ));

			g_BPGI.set_parameters( para,p_RTV,p_SRV,&light_color[0] );
			g_BPGI.OnD3D10FrameRender(render_ogre,render_scene,g_SampleUI,g_MeshScene,fSubLightSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
		}
	}
//-----------------------------------------------------------------------------------

	int light_idx = 0;
	float unshadow_factor;
	int num_applied_light = NUM_APPLIED_LIGHT;
	if( num_applied_light == 0 )
		unshadow_factor = 0;
	else
		unshadow_factor = 0.2 / num_applied_light;

	for( ; light_idx < NUM_APPLIED_LIGHT; ++light_idx )
	{
		int cam_idx = light_idx;
		if( light_idx == 0 )
		{
			cam_idx = 1;
		}
		// MESH parameters may change inside loop, so reset them every time
		g_MeshScene.set_parameters( render_ogre, render_scene, render_fan, false );

		//g_fFilterSize = light_size[light_idx];

		NVUTCamera& g_LCameraRef = g_LCamera[cam_idx];//potential dangerous here
		g_fLightZn = light_ZNS[light_idx];

		D3DXMATRIX mLightView;
		// here we compute light viewprojection so that light oversees the whole scene
		D3DXMATRIX mTranslate;

		D3DXMatrixInverse(&mTranslate, NULL, g_LCameraRef.GetWorldMatrix());
		D3DXMatrixMultiply(&mLightView, &mTranslate, g_LCameraRef.GetViewMatrix());
		g_LCameraRef.SetProjParams(light_view_angle[light_idx], 1.0, g_fLightZn, g_fLightZn + LIGHT_ZF_DELTA);

		// render shadow map
		unsigned iTmp = g_SampleUI.GetCheckBox(IDC_BDUMP_SHADOWMAP)->GetChecked();
		//ssmap.Render(pDev10, &g_MeshScene, g_LCameraRef,fTime,fElapsedTime,iTmp);

		pDev10->RSSetState(g_pRenderState);

		if( ( light_idx + g_nNumLightSample * g_nNumLightSample ) % 2 == 0 )
		{
			p_RTV = g_pPingpongBuffer[0]->m_pRTView;
			p_SRV = g_pPingpongBuffer[1]->m_pSRView;
		}
		else
		{
			p_RTV = g_pPingpongBuffer[1]->m_pRTView;
			p_SRV = g_pPingpongBuffer[0]->m_pSRView;
		}

		if( ShadowAlgorithm == STANDARD_BP )
		{
			g_ABP.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
			g_ABP.OnD3D10FrameRender(g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
		}
		else if( ShadowAlgorithm == BP_NOSMP )
		{
			g_ABP_nosmp.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
			g_ABP_nosmp.OnD3D10FrameRender(g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
		}
		else if( ShadowAlgorithm == MARCHING_BP )
		{
			g_MBP.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
			g_MBP.OnD3D10FrameRender(g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
		}
		else if( ShadowAlgorithm == HIR_EDGE_EXTRACTION )
		{
			g_HEEBP.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
			g_HEEBP.OnD3D10FrameRender(g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
		}
		else if( ShadowAlgorithm == HIR_BP )
		{
			g_HBP.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
			g_HBP.OnD3D10FrameRender(g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
		}
		else if( ShadowAlgorithm == BP_GI )
		{
			g_BPGI.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
			g_BPGI.OnD3D10FrameRender(render_ogre,render_scene,g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
		}
		else if( ShadowAlgorithm == NO_SHADOW_ALGORITHM  )
		{
			g_NoShadow.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
			g_NoShadow.OnD3D10FrameRender(g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
		}
		else if( ShadowAlgorithm == SINGLE_LIGHT  )
		{
			if( light_idx < 0 )
			{
				g_BPGI.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
				g_BPGI.OnD3D10FrameRender(render_ogre,render_scene,g_SampleUI,g_MeshScene,fSubLightSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
			}
			else
			{
				V(g_NoShadow.m_pEffect->GetVariableByName("g_fLumiFactor")->AsScalar()->SetFloat( unshadow_factor ));
				g_NoShadow.set_parameters( para,p_RTV,p_SRV,&light_color[light_idx] );
				g_NoShadow.OnD3D10FrameRender(g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);
			}
		}

		//render light
		
		{
			D3DXMATRIX mTmp, mWorldView;
			D3DXMatrixInverse(&mTmp, NULL, g_CameraRef.GetWorldMatrix());
			D3DXMatrixMultiply(&mWorldView, &mTmp, g_CameraRef.GetViewMatrix());
			D3DXMatrixMultiply(&mWorldViewProj, &mWorldView, g_CameraRef.GetProjMatrix());

			D3DXMATRIX mLightViewInv;
			D3DXMatrixInverse(&mLightViewInv, NULL, g_LCameraRef.GetViewMatrix());
			D3DXMATRIX mLightViewInvWorldViewProj;
			D3DXMatrixMultiply(&mLightViewInvWorldViewProj, &mLightViewInv, &mWorldViewProj);
			V(g_ABP.m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mLightViewInvWorldViewProj));
			g_ABP.m_pEffect->GetTechniqueByName("RenderNoShadows")->GetPassByIndex(0)->Apply(0);

		    D3D10_RASTERIZER_DESC RasterizerState;
			RasterizerState.FillMode = D3D10_FILL_SOLID;
			RasterizerState.CullMode = D3D10_CULL_NONE;
			RasterizerState.FrontCounterClockwise = true;
			RasterizerState.DepthBias = false;
			RasterizerState.DepthBiasClamp = 0;
			RasterizerState.SlopeScaledDepthBias = 0;
			RasterizerState.DepthClipEnable = true;
			RasterizerState.ScissorEnable = false;
			RasterizerState.MultisampleEnable = false;
			RasterizerState.AntialiasedLineEnable = false;
			V(pDev10->CreateRasterizerState(&RasterizerState, &g_pRenderState));


			//pDev10->RSSetState(g_pRenderState);
			//pDev10->IASetInputLayout(g_pMaxLayout);
			//g_MeshLight.Render(pDev10);
		}
	}
	
	if( ( light_idx + g_nNumLightSample * g_nNumLightSample ) % 2 == 0 )
	{
		p_RTV = g_pPingpongBuffer[0]->m_pRTView;
		p_SRV = g_pPingpongBuffer[1]->m_pSRView;
	}
	else
	{
		p_RTV = g_pPingpongBuffer[1]->m_pRTView;
		p_SRV = g_pPingpongBuffer[0]->m_pSRView;
	}

	
	D3DXMATRIX mMatrixScale;
	D3DXMATRIX mMatrixScaleWVP;
	D3DXMatrixScaling( &mMatrixScale,(FLOAT)5,(FLOAT)5,(FLOAT)5 );
	D3DXMatrixMultiply( &mMatrixScaleWVP, &mMatrixScale, &mWorldViewProj );
	ID3D10RenderTargetView* pOrigRTV = DXUTGetD3D10RenderTargetView();
	pDev10->OMSetRenderTargets(1,&pOrigRTV,pDSV);

	g_MeshScene.set_parameters( render_ogre,render_scene, render_fan );
	g_Final.set_parameters( para, pOrigRTV, p_SRV,NULL );
	NVUTCamera& g_LCameraRef = g_LCamera[0];

	V(g_Final.m_pEffect->GetVariableByName("LightLumi0")->AsShaderResource()->SetResource( g_pLightLumiBuffer[0]->m_pSRView ));
	V(g_Final.m_pEffect->GetVariableByName("LightLumi1")->AsShaderResource()->SetResource( g_pLightLumiBuffer[1]->m_pSRView ));
	V(g_Final.m_pEffect->GetVariableByName("LightLumi2")->AsShaderResource()->SetResource( g_pLightLumiBuffer[2]->m_pSRView ));
	V(g_Final.m_pEffect->GetVariableByName("LightLumi3")->AsShaderResource()->SetResource( g_pLightLumiBuffer[3]->m_pSRView ));
	V(g_Final.m_pEffect->GetVariableByName("LightLumi4")->AsShaderResource()->SetResource( g_pLightLumiBuffer[4]->m_pSRView ));
	V(g_Final.m_pEffect->GetVariableByName("LightLumi5")->AsShaderResource()->SetResource( g_pLightLumiBuffer[5]->m_pSRView ));
	V(g_Final.m_pEffect->GetVariableByName("LightLumi6")->AsShaderResource()->SetResource( g_pLightLumiBuffer[6]->m_pSRView ));
	V(g_Final.m_pEffect->GetVariableByName("LightLumi7")->AsShaderResource()->SetResource( g_pLightLumiBuffer[7]->m_pSRView ));
	
	//g_pSkyBox->OnFrameRender( mMatrixScaleWVP );
	g_Final.OnD3D10FrameRender(g_SampleUI,g_MeshScene,g_fFilterSize,ssmap,g_CameraRef,g_LCameraRef,pDev10,fTime,fElapsedTime,pUserContext);

    // render UI
    if (g_bShowUI)
    {

        RenderText();
        g_SampleUI.OnRender(fElapsedTime);
        g_HUD.OnRender(fElapsedTime);
    }

if( g_SampleUI.GetCheckBox( IDC_FRAME_DUMP )->GetChecked() )
{
  static int g_Frame = 0;
  IDXGISwapChain* pSwapChain = DXUTGetDXGISwapChain();
  ID3D10Texture2D* pRT;
  pSwapChain->GetBuffer(0, __uuidof(pRT), reinterpret_cast<void**>(&pRT));
  WCHAR filename[32];
  StringCchPrintf(filename, 100, L"d:\\screenshot%.3d.bmp", g_Frame); 
  D3DX10SaveTextureToFile(pRT, D3DX10_IFF_BMP, filename);
  pRT->Release();
  ++g_Frame;
}
}
//--------------------------------------------------------------------------------------
// Release D3D10 resources created in OnD3D10ResizedSwapChain 
//--------------------------------------------------------------------------------------
void CALLBACK OnD3D10SwapChainReleasing( void* pUserContext )
{
    g_DialogResourceManager.OnD3D10ReleasingSwapChain();
    ssmap.OnWindowResize();
	g_pSkyBox->OnReleasingSwapChain();
}
//--------------------------------------------------------------------------------------
// Release D3D10 resources created in OnD3D10CreateDevice 
//--------------------------------------------------------------------------------------
void CALLBACK OnD3D10DestroyDevice( void* pUserContext )
{
	//light management
	for( int light_idx = 0; light_idx < NUM_LIGHT; ++light_idx )
	{
		g_pLightLumiBuffer[light_idx]->OnD3D10DestroyDevice(pUserContext);
	}
	for( int p_idx = 0 ; p_idx < 2 ; ++p_idx )
	{
		g_pPingpongBuffer[p_idx]->OnD3D10DestroyDevice(pUserContext);
	}


	//-----------------------------------------

	g_ABP.OnD3D10DestroyDevice(pUserContext);
	g_NoShadow.OnD3D10DestroyDevice(pUserContext);
	g_BPGI.OnD3D10DestroyDevice(pUserContext);
	g_HBP.OnD3D10DestroyDevice(pUserContext);
	g_HEEBP.OnD3D10DestroyDevice(pUserContext);
	g_MBP.OnD3D10DestroyDevice(pUserContext);
	g_ABP_nosmp.OnD3D10DestroyDevice(pUserContext);
	g_Final.OnD3D10DestroyDevice(pUserContext);
	ssmap.OnDestroy();

    g_DialogResourceManager.OnD3D10DestroyDevice();
    g_D3DSettingsDlg.OnD3D10DestroyDevice();

    SAFE_RELEASE(g_pFont10);
    SAFE_RELEASE(g_pSprite10);
    SAFE_RELEASE(g_pRenderState);
    SAFE_RELEASE(g_pMaxLayout);

    g_MeshScene.Destroy();
    g_MeshLight.Destroy();

    g_pSkyBox->OnDestroyDevice();
	g_pEnvMap->OnDestroyDevice();
}
