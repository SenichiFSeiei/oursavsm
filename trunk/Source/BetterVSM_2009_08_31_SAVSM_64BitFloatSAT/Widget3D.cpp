#include "Widget3D.h"
#include <S3UTcamera.h>

Widget3D::Widget3D()
{
	m_pEffect = NULL;
	m_pRenderState = NULL;
}

HRESULT Widget3D::OnD3D10CreateDevice( ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
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

void Widget3D::DrawLightSource( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef,float par_fFilterSize )
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

void Widget3D::OnD3D10FrameRender( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef, float par_fFilterSize )
{
	DrawLightSource( pDev10,par_CameraRef,par_LCameraRef, par_fFilterSize );
}

void Widget3D::OnD3D10DestroyDevice()
{
	SAFE_RELEASE(m_pEffect);
}
