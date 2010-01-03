#ifndef BLEND_UTIL
#define BLEND_UTIL

class BlendingUtility
{
public:
	FLOAT			  OriginalBlendFactor[4];
	UINT		      OriginalSampleMask;
	ID3D10BlendState* pOriginalBlendState;

	ID3D10BlendState* m_pSceneBlendStateInitial;
	ID3D10BlendState* m_pSceneBlendStateOn;

	HRESULT OnD3D10CreateDevice(ID3D10Device *pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void *pUserContext);
	void OnD3D10DestroyDevice( void* pUserContext );

};

HRESULT BlendingUtility::OnD3D10CreateDevice(ID3D10Device *pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void *pUserContext)
{
	SAFE_RELEASE(m_pSceneBlendStateInitial);
	SAFE_RELEASE(m_pSceneBlendStateOn);
	SAFE_RELEASE(pOriginalBlendState);
	D3D10_BLEND_DESC StateDesc;
	ZeroMemory( &StateDesc, sizeof(D3D10_BLEND_DESC) );
	StateDesc.AlphaToCoverageEnable = FALSE;
	StateDesc.BlendEnable[0] = TRUE;
	StateDesc.SrcBlend = D3D10_BLEND_SRC_ALPHA;
	StateDesc.DestBlend = D3D10_BLEND_ZERO;
	StateDesc.BlendOp = D3D10_BLEND_OP_ADD;
	StateDesc.SrcBlendAlpha = D3D10_BLEND_ZERO;
	StateDesc.DestBlendAlpha = D3D10_BLEND_ZERO;
	StateDesc.BlendOpAlpha = D3D10_BLEND_OP_ADD;
	StateDesc.RenderTargetWriteMask[0] = 0xf;
	pDev10->CreateBlendState( &StateDesc, &m_pSceneBlendStateInitial );
	StateDesc.DestBlend = D3D10_BLEND_ONE;
	pDev10->CreateBlendState( &StateDesc, &m_pSceneBlendStateOn );

	OriginalSampleMask = 0;
	pDev10->OMGetBlendState( &pOriginalBlendState, OriginalBlendFactor, &OriginalSampleMask );

	return S_OK;

}

void BlendingUtility::OnD3D10DestroyDevice( void* pUserContext )
{
	SAFE_RELEASE(m_pSceneBlendStateInitial);
	SAFE_RELEASE(m_pSceneBlendStateOn);
	SAFE_RELEASE(pOriginalBlendState);
}

#endif