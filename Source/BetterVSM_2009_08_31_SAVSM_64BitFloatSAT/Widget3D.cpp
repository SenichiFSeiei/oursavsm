#include "Widget3D.h"
#include <S3UTcamera.h>
#include <math.h>

Widget3D::Widget3D()
{
	m_pEffect = NULL;
	m_pRenderState = NULL;
}

HRESULT Widget3D::CreateShader(ID3D10Device *pDev10)
{
	HRESULT hr;

	WCHAR str[MAX_PATH];
    V_RETURN(DXUTFindDXSDKMediaFileCch(str, MAX_PATH, L"Widget3D.fx" ));
    ID3D10Blob *pErrors;
    if (D3DX10CreateEffectFromFile(str, NULL, NULL, "fx_4_0", D3D10_SHADER_DEBUG|D3D10_SHADER_SKIP_OPTIMIZATION, 0, pDev10, NULL, NULL, &m_pEffect, &pErrors, &hr) != S_OK)
    {
        MessageBoxA(NULL, (char *)pErrors->GetBufferPointer(), "Compilation error", MB_OK);
        exit(0);
    }
	return S_OK;
}

HRESULT Widget3D::OnD3D10CreateDevice( ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	CreateShader( pDev10 );
	ReadParameters();
	return S_OK;

}

void Widget3D::DrawLightSource( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef,float par_fFilterSize )
{
	HRESULT hr;
	//Draw Light Source
	
	D3DXMATRIX mTmp, mWorldView, mWorldViewProj;
	D3DXMatrixInverse(&mTmp, NULL, par_CameraRef.GetWorldMatrix());
	D3DXMatrixMultiply(&mWorldView, &mTmp, par_CameraRef.GetViewMatrix());
	D3DXMatrixMultiply(&mWorldViewProj, &mWorldView, par_CameraRef.GetProjMatrix());

	m_vLight = *par_LCameraRef.GetEyePt();
	m_fLightSize = par_fFilterSize;

	D3DXMATRIX mLightViewInv;
	D3DXMatrixInverse(&mLightViewInv, NULL, par_LCameraRef.GetViewMatrix());
	D3DXMATRIX mLightViewInvWorldViewProj;
	D3DXMatrixMultiply(&mLightViewInvWorldViewProj, &mLightViewInv, &mWorldViewProj);
	V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mLightViewInvWorldViewProj));
	

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
	V(pDev10->CreateRasterizerState(&RasterizerState, &m_pRenderState));

	pDev10->RSSetState(m_pRenderState);

	ID3D10InputLayout *pVertexLayout;

	D3D10_INPUT_ELEMENT_DESC layout[] =
	{
	  { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },  
	};

	D3D10_PASS_DESC PassDesc;
	m_pEffect->GetTechniqueByName( "RenderLight" )->GetPassByIndex(0)->GetDesc( &PassDesc );   
	V(pDev10->CreateInputLayout( layout,1, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &pVertexLayout ));

	float FilterSize = par_fFilterSize * 5;

	SVertexTexcoords frontvertices[6] =
	{
	  { D3DXVECTOR3(-FilterSize,  FilterSize, 0.0f ) },
	  { D3DXVECTOR3( FilterSize, -FilterSize, 0.0f ) },
	  { D3DXVECTOR3(-FilterSize, -FilterSize, 0.0f ) },

	  { D3DXVECTOR3(-FilterSize,  FilterSize, 0.0f ) },
	  { D3DXVECTOR3( FilterSize,  FilterSize, 0.0f ) },
	  { D3DXVECTOR3( FilterSize, -FilterSize, 0.0f ) },
	};

	SVertexTexcoords backvertices[6] =
	{
	  { D3DXVECTOR3(-FilterSize, -FilterSize, 0.0f ) },
	  { D3DXVECTOR3( FilterSize, -FilterSize, 0.0f ) },
	  { D3DXVECTOR3(-FilterSize,  FilterSize, 0.0f ) },

	  { D3DXVECTOR3( FilterSize, -FilterSize, 0.0f ) },
	  { D3DXVECTOR3( FilterSize,  FilterSize, 0.0f ) },
	  { D3DXVECTOR3(-FilterSize,  FilterSize, 0.0f ) },
	};

	ID3D10Buffer* pVertexBuffer1 = NULL;
	ID3D10Buffer* pVertexBuffer2 = NULL;

	D3D10_BUFFER_DESC bd;
	bd.Usage = D3D10_USAGE_DEFAULT;
	bd.ByteWidth = sizeof( SVertexTexcoords ) * 6;
	bd.BindFlags = D3D10_BIND_VERTEX_BUFFER;
	bd.CPUAccessFlags = 0;
	bd.MiscFlags = 0;
	D3D10_SUBRESOURCE_DATA InitData;
	InitData.pSysMem = frontvertices;
	V(pDev10->CreateBuffer( &bd, &InitData, &pVertexBuffer1 ));
	InitData.pSysMem = backvertices;
	V(pDev10->CreateBuffer( &bd, &InitData, &pVertexBuffer2 ));
	
	UINT Stride = sizeof( SVertexTexcoords );
	UINT Offset = 0;
	pDev10->IASetInputLayout(pVertexLayout);

	m_pEffect->GetTechniqueByName("RenderLight")->GetPassByIndex(0)->Apply(0);

	pDev10->IASetVertexBuffers( 0, 1, &pVertexBuffer1, &Stride, &Offset );
	pDev10->IASetPrimitiveTopology( D3D10_PRIMITIVE_TOPOLOGY_TRIANGLELIST );
	pDev10->Draw( 6, 0 );

	pDev10->IASetVertexBuffers( 0, 1, &pVertexBuffer2, &Stride, &Offset );
	pDev10->IASetPrimitiveTopology( D3D10_PRIMITIVE_TOPOLOGY_TRIANGLELIST );
	pDev10->Draw( 6, 0 );

	SAFE_RELEASE(pVertexLayout);
	SAFE_RELEASE(pVertexBuffer1);
	SAFE_RELEASE(pVertexBuffer2);
	SAFE_RELEASE(m_pRenderState);
	
}
void Widget3D::DrawAxis( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef,float par_fFilterSize )
{
	HRESULT hr;
		//Draw Light Source
	
	D3DXMATRIX mTmp, mWorldView, mWorldViewProj;
	D3DXMatrixInverse(&mTmp, NULL, par_CameraRef.GetWorldMatrix());
	D3DXMatrixMultiply(&mWorldView, &mTmp, par_CameraRef.GetViewMatrix());
	D3DXMatrixMultiply(&mWorldViewProj, &mWorldView, par_CameraRef.GetProjMatrix());

	D3DXMATRIX mLightViewInv;
	D3DXMatrixInverse(&mLightViewInv, NULL, par_LCameraRef.GetViewMatrix());
	D3DXMATRIX mLightViewInvWorldViewProj;
	D3DXMatrixMultiply(&mLightViewInvWorldViewProj, &mLightViewInv, &mWorldViewProj);
	V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mLightViewInvWorldViewProj));
	//V(g_ABP.m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mWorldViewProj));
	

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
	V(pDev10->CreateRasterizerState(&RasterizerState, &m_pRenderState));

	pDev10->RSSetState(m_pRenderState);

	ID3D10InputLayout *pVertexLayout;

	D3D10_INPUT_ELEMENT_DESC layout[] =
	{
	  { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },  
	};

	D3D10_PASS_DESC PassDesc;
	m_pEffect->GetTechniqueByName( "RenderAxis" )->GetPassByName("X")->GetDesc( &PassDesc );   
	V(pDev10->CreateInputLayout( layout,1, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &pVertexLayout ));

	float FilterSize = par_fFilterSize * 5;

	SVertexTexcoords axisvertices[6] =
	{
	  { D3DXVECTOR3( 0.0f, 0.0f, 0.0f ) },
	  { D3DXVECTOR3( 2 * FilterSize, 0.0f, 0.0f ) },
	  { D3DXVECTOR3( 0.0f, 0.0f, 0.0f ) },
	  { D3DXVECTOR3( 0.0f, 2 * FilterSize, 0.0f ) },
	  { D3DXVECTOR3( 0.0f, 0.0f, 0.0f ) },
	  { D3DXVECTOR3( 0.0f, 0.0f, 2 * FilterSize ) },
	};

	ID3D10Buffer* pVertexBuffer1 = NULL;

	D3D10_BUFFER_DESC bd;
	bd.Usage = D3D10_USAGE_DEFAULT;
	bd.ByteWidth = sizeof( SVertexTexcoords ) * 6;
	bd.BindFlags = D3D10_BIND_VERTEX_BUFFER;
	bd.CPUAccessFlags = 0;
	bd.MiscFlags = 0;
	D3D10_SUBRESOURCE_DATA InitData;
	InitData.pSysMem = axisvertices;
	V(pDev10->CreateBuffer( &bd, &InitData, &pVertexBuffer1 ));
	
	UINT Stride = sizeof( SVertexTexcoords );
	UINT Offset = 0;
	pDev10->IASetInputLayout(pVertexLayout);

	m_pEffect->GetTechniqueByName("RenderAxis")->GetPassByName("X")->Apply(0);

	pDev10->IASetVertexBuffers( 0, 1, &pVertexBuffer1, &Stride, &Offset );
	pDev10->IASetPrimitiveTopology( D3D10_PRIMITIVE_TOPOLOGY_LINELIST  );
	pDev10->Draw( 2, 0 );
	
	m_pEffect->GetTechniqueByName("RenderAxis")->GetPassByName("Y")->Apply(0);
	pDev10->Draw( 2, 2 );

	m_pEffect->GetTechniqueByName("RenderAxis")->GetPassByName("Z")->Apply(0);
	pDev10->Draw( 2, 4 );

	SAFE_RELEASE(pVertexLayout);
	SAFE_RELEASE(pVertexBuffer1);
	SAFE_RELEASE(m_pRenderState);
	
}

void Widget3D::DrawFrustum( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef,float par_fFilterSize )
{
	HRESULT hr;
		//Draw Light Source
	
	D3DXMATRIX mTmp, mWorldView, mWorldViewProj;
	D3DXMatrixInverse(&mTmp, NULL, par_CameraRef.GetWorldMatrix());
	D3DXMatrixMultiply(&mWorldView, &mTmp, par_CameraRef.GetViewMatrix());
	D3DXMatrixMultiply(&mWorldViewProj, &mWorldView, par_CameraRef.GetProjMatrix());

	D3DXMATRIX mLightViewInv;
	D3DXMatrixInverse(&mLightViewInv, NULL, par_LCameraRef.GetViewMatrix());
	D3DXMATRIX mLightViewInvWorldViewProj;
	D3DXMatrixMultiply(&mLightViewInvWorldViewProj, &mLightViewInv, &mWorldViewProj);
	V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mLightViewInvWorldViewProj));
	

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
	V(pDev10->CreateRasterizerState(&RasterizerState, &m_pRenderState));

	pDev10->RSSetState(m_pRenderState);

	ID3D10InputLayout *pVertexLayout;

	D3D10_INPUT_ELEMENT_DESC layout[] =
	{
	  { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },  
	};

	D3D10_PASS_DESC PassDesc;
	m_pEffect->GetTechniqueByName( "RenderFrustum" )->GetPassByIndex(0)->GetDesc( &PassDesc );   
	V(pDev10->CreateInputLayout( layout,1, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &pVertexLayout ));

	D3DXMATRIX mat_light_proj = *par_LCameraRef.GetProjMatrix();

	float w = mat_light_proj._11;
	float light_zn = par_LCameraRef.GetNearClip();
	float light_zf = par_LCameraRef.GetFarClip();
	m_fCtrledLightZn = light_zn;
	m_fCtrledLightZf = light_zf;

	float near_plane_width = 2*light_zn/w;
	float far_plane_width = near_plane_width * light_zf / light_zn;


	SVertexTexcoords frustumvertices[24] =
	{
	  { D3DXVECTOR3( 0.0f, 0.0f, 0.0f ) },
	  { D3DXVECTOR3( far_plane_width/2, far_plane_width/2, light_zf ) },
	  { D3DXVECTOR3( 0.0f, 0.0f, 0.0f ) },
	  { D3DXVECTOR3( far_plane_width/2, -far_plane_width/2, light_zf ) },
	  { D3DXVECTOR3( 0.0f, 0.0f, 0.0f ) },
	  { D3DXVECTOR3( -far_plane_width/2, -far_plane_width/2, light_zf ) },
	  { D3DXVECTOR3( 0.0f, 0.0f, 0.0f ) },
	  { D3DXVECTOR3( -far_plane_width/2, far_plane_width/2, light_zf ) },
	  
	  { D3DXVECTOR3( near_plane_width/2, near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3( -near_plane_width/2, near_plane_width/2, light_zn ) },
	  
	  { D3DXVECTOR3( near_plane_width/2, near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3( near_plane_width/2, -near_plane_width/2, light_zn ) },
	  
	  { D3DXVECTOR3( -near_plane_width/2, -near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3( -near_plane_width/2, near_plane_width/2, light_zn ) },
	  
	  { D3DXVECTOR3( -near_plane_width/2, -near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3( near_plane_width/2, -near_plane_width/2, light_zn ) },
	  
	  { D3DXVECTOR3( far_plane_width/2, far_plane_width/2, light_zf ) },
	  { D3DXVECTOR3( -far_plane_width/2, far_plane_width/2, light_zf ) },
	  
	  { D3DXVECTOR3( far_plane_width/2, far_plane_width/2, light_zf ) },
	  { D3DXVECTOR3( far_plane_width/2, -far_plane_width/2, light_zf ) },
	  
	  { D3DXVECTOR3( -far_plane_width/2, -far_plane_width/2, light_zf ) },
	  { D3DXVECTOR3( -far_plane_width/2, far_plane_width/2, light_zf ) },
	  
	  { D3DXVECTOR3( -far_plane_width/2, -far_plane_width/2, light_zf ) },
	  { D3DXVECTOR3( far_plane_width/2, -far_plane_width/2, light_zf ) },

	};

	ID3D10Buffer* pVertexBuffer1 = NULL;

	D3D10_BUFFER_DESC bd;
	bd.Usage = D3D10_USAGE_DEFAULT;
	bd.ByteWidth = sizeof( SVertexTexcoords ) * 24;
	bd.BindFlags = D3D10_BIND_VERTEX_BUFFER;
	bd.CPUAccessFlags = 0;
	bd.MiscFlags = 0;
	D3D10_SUBRESOURCE_DATA InitData;
	InitData.pSysMem = frustumvertices;
	V(pDev10->CreateBuffer( &bd, &InitData, &pVertexBuffer1 ));
	
	UINT Stride = sizeof( SVertexTexcoords );
	UINT Offset = 0;
	pDev10->IASetInputLayout(pVertexLayout);

	m_pEffect->GetTechniqueByName("RenderFrustum")->GetPassByIndex(0)->Apply(0);

	pDev10->IASetVertexBuffers( 0, 1, &pVertexBuffer1, &Stride, &Offset );
	pDev10->IASetPrimitiveTopology( D3D10_PRIMITIVE_TOPOLOGY_LINELIST  );
	pDev10->Draw( 24, 0 );
	
	SAFE_RELEASE(pVertexLayout);
	SAFE_RELEASE(pVertexBuffer1);
	SAFE_RELEASE(m_pRenderState);
	
}

void Widget3D::DrawNearPlane( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef,float par_fFilterSize )
{
	HRESULT hr;
	//Draw Near Plane with shadow map
    V(m_pEffect->GetVariableByName("TexDepthMap")->AsShaderResource()->SetResource(m_pSsmap->m_pDepthSRView[0]));
	
	D3DXMATRIX mTmp, mWorldView, mWorldViewProj;
	D3DXMatrixInverse(&mTmp, NULL, par_CameraRef.GetWorldMatrix());
	D3DXMatrixMultiply(&mWorldView, &mTmp, par_CameraRef.GetViewMatrix());
	D3DXMatrixMultiply(&mWorldViewProj, &mWorldView, par_CameraRef.GetProjMatrix());

	m_vLight = *par_LCameraRef.GetEyePt();
	m_fLightSize = par_fFilterSize;

	D3DXMATRIX mLightViewInv;
	D3DXMatrixInverse(&mLightViewInv, NULL, par_LCameraRef.GetViewMatrix());
	D3DXMATRIX mLightViewInvWorldViewProj;
	D3DXMatrixMultiply(&mLightViewInvWorldViewProj, &mLightViewInv, &mWorldViewProj);
	V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mLightViewInvWorldViewProj));
	

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
	V(pDev10->CreateRasterizerState(&RasterizerState, &m_pRenderState));

	pDev10->RSSetState(m_pRenderState);

	ID3D10InputLayout *pVertexLayout;

	D3D10_INPUT_ELEMENT_DESC layout[] =
	{
	  { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },  
	};

	D3D10_PASS_DESC PassDesc;
	m_pEffect->GetTechniqueByName( "RenderLight" )->GetPassByIndex(0)->GetDesc( &PassDesc );   
	V(pDev10->CreateInputLayout( layout,1, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &pVertexLayout ));

	float FilterSize = par_fFilterSize * 5;

	D3DXMATRIX mat_light_proj = *par_LCameraRef.GetProjMatrix();

	float w = mat_light_proj._11;
	float light_zn = par_LCameraRef.GetNearClip();
	float light_zf = par_LCameraRef.GetFarClip();
	m_fCtrledLightZn = light_zn;
	m_fCtrledLightZf = light_zf;

	float near_plane_width = 2*light_zn/w;
	float far_plane_width = near_plane_width * light_zf / light_zn;

	V(m_pEffect->GetVariableByName("g_fNearPlaneWidth")->AsScalar()->SetFloat(near_plane_width));

	SVertexTexcoords frontvertices[6] =
	{
	  { D3DXVECTOR3( -near_plane_width/2, near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3(  near_plane_width/2,-near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3( -near_plane_width/2,-near_plane_width/2, light_zn ) },

	  { D3DXVECTOR3( -near_plane_width/2, near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3(  near_plane_width/2, near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3(  near_plane_width/2,-near_plane_width/2, light_zn ) },	  
	};
	SVertexTexcoords backvertices[6] =
	{
	  { D3DXVECTOR3( -near_plane_width/2,-near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3(  near_plane_width/2,-near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3( -near_plane_width/2, near_plane_width/2, light_zn ) },

	  { D3DXVECTOR3(  near_plane_width/2,-near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3(  near_plane_width/2, near_plane_width/2, light_zn ) },
	  { D3DXVECTOR3( -near_plane_width/2, near_plane_width/2, light_zn ) },	  
	};

	ID3D10Buffer* pVertexBuffer1 = NULL;
	ID3D10Buffer* pVertexBuffer2 = NULL;

	D3D10_BUFFER_DESC bd;
	bd.Usage = D3D10_USAGE_DEFAULT;
	bd.ByteWidth = sizeof( SVertexTexcoords ) * 6;
	bd.BindFlags = D3D10_BIND_VERTEX_BUFFER;
	bd.CPUAccessFlags = 0;
	bd.MiscFlags = 0;
	D3D10_SUBRESOURCE_DATA InitData;
	InitData.pSysMem = frontvertices;
	V(pDev10->CreateBuffer( &bd, &InitData, &pVertexBuffer1 ));
	InitData.pSysMem = backvertices;
	V(pDev10->CreateBuffer( &bd, &InitData, &pVertexBuffer2 ));
	
	UINT Stride = sizeof( SVertexTexcoords );
	UINT Offset = 0;
	pDev10->IASetInputLayout(pVertexLayout);

	m_pEffect->GetTechniqueByName("RenderNearPlane")->GetPassByIndex(0)->Apply(0);

	pDev10->IASetVertexBuffers( 0, 1, &pVertexBuffer1, &Stride, &Offset );
	pDev10->IASetPrimitiveTopology( D3D10_PRIMITIVE_TOPOLOGY_TRIANGLELIST );
	pDev10->Draw( 6, 0 );

	pDev10->IASetVertexBuffers( 0, 1, &pVertexBuffer2, &Stride, &Offset );
	pDev10->IASetPrimitiveTopology( D3D10_PRIMITIVE_TOPOLOGY_TRIANGLELIST );
	pDev10->Draw( 6, 0 );

	SAFE_RELEASE(pVertexLayout);
	SAFE_RELEASE(pVertexBuffer1);
	SAFE_RELEASE(pVertexBuffer2);
	SAFE_RELEASE(m_pRenderState);
	
}

void Widget3D::OnD3D10FrameRender( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef, float par_fFilterSize )
{
	if( m_bShaderChanged )
	{
		CreateShader(pDev10);
		m_bShaderChanged = false;
	}

	DrawLightSource( pDev10,par_CameraRef,par_LCameraRef, par_fFilterSize );
	DrawAxis( pDev10,par_CameraRef,par_LCameraRef, par_fFilterSize );
	DrawNearPlane( pDev10,par_CameraRef,par_LCameraRef, par_fFilterSize );
	DrawFrustum( pDev10,par_CameraRef,par_LCameraRef, par_fFilterSize );
}

void Widget3D::OnD3D10DestroyDevice()
{
	SAFE_RELEASE(m_pEffect);
}

void Widget3D::DumpParameters()
{
	FILE *fp = fopen("SceneParameters.txt","w");

	fprintf( fp, "%f %f %f\n", m_vLight.x,m_vLight.y,m_vLight.z );
	fprintf( fp, "%f\n", m_fLightSize );
	fprintf( fp, "%f\n",m_fCtrledLightZn );
	fprintf( fp, "%f\n",m_fCtrledLightZf );
	fprintf( fp, "%f\n",m_fCtrledLightFov );

	fclose( fp );
}

void Widget3D::ReadParameters()
{
	
	FILE *fp = fopen("SceneParameters.txt","r");
	
	fscanf( fp, "%f %f %f\n", &m_vLight.x,&m_vLight.y,&m_vLight.z );
	fscanf( fp, "%f\n", &m_fLightSize );
	fscanf( fp, "%f\n", &m_fCtrledLightZn );
	fscanf( fp, "%f\n", &m_fCtrledLightZf );
	fscanf( fp, "%f\n", &m_fCtrledLightFov );
	fclose( fp );
}

void Widget3D::ProvideParameters( D3DXVECTOR3& vLight, float &fLightSize, float &fCtrledLightZn, float &fCtrledLightZf, float &fCtrledLightFov)
{
	vLight = m_vLight;
	fLightSize = m_fLightSize;
	fCtrledLightZn   = m_fCtrledLightZn; 
	fCtrledLightZf   = m_fCtrledLightZf; 
	fCtrledLightFov  = m_fCtrledLightFov;
}

