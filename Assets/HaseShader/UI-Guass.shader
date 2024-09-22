// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "UI/Guass"
{
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)

        _StencilComp ("Stencil Comparison", Float) = 8
        _Stencil ("Stencil ID", Float) = 0
        _StencilOp ("Stencil Operation", Float) = 0
        _StencilWriteMask ("Stencil Write Mask", Float) = 255
        _StencilReadMask ("Stencil Read Mask", Float) = 255

        _ColorMask ("Color Mask", Float) = 15

        _Sigma ("ぼかし", Float) = 10
        _KernelSize ("半径", Int) = 35

        [Toggle(UNITY_UI_ALPHACLIP)] _UseUIAlphaClip ("Use Alpha Clip", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "Queue"="Transparent"
            "IgnoreProjector"="True"
            "RenderType"="Transparent"
            "PreviewType"="Plane"
            "CanUseSpriteAtlas"="True"
        }

        Stencil
        {
            Ref [_Stencil]
            Comp [_StencilComp]
            Pass [_StencilOp]
            ReadMask [_StencilReadMask]
            WriteMask [_StencilWriteMask]
        }

        Cull Off
        Lighting Off
        ZWrite Off
        ZTest [unity_GUIZTestMode]
        Blend One OneMinusSrcAlpha
        ColorMask [_ColorMask]

        Pass
        {
            Name "Guass"
        CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

            #include "UnityCG.cginc"
            #include "UnityUI.cginc"

            #pragma multi_compile_local _ UNITY_UI_CLIP_RECT
            #pragma multi_compile_local _ UNITY_UI_ALPHACLIP

            struct appdata_t
            {
                float4 vertex   : POSITION;
                float4 color    : COLOR;
                float2 texcoord : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex   : SV_POSITION;
                fixed4 color    : COLOR;
                float2 texcoord  : TEXCOORD0;
                float4 worldPosition : TEXCOORD1;
                float4  mask : TEXCOORD2;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            fixed4 _Color;
            fixed4 _TextureSampleAdd;
            float4 _ClipRect;
            float4 _MainTex_ST;
            float4 _MainTex_TexelSize;
            float _Sigma;
            float _UIMaskSoftnessX;
            float _UIMaskSoftnessY;
            int _UIVertexColorAlwaysGammaSpace;
            int _KernelSize;

            // ガウシアンカーネルのサイズを設定
            // #ifdef MEDIUM_KERNEL
             #define  35
            // #elif BIG_KERNEL
            // #define KERNEL_SIZE 127
            // #else
            // #define KERNEL_SIZE 7
            // #endif

            #define PI 3.14159265

            v2f vert(appdata_t v)
            {
                v2f OUT;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                float4 vPosition = UnityObjectToClipPos(v.vertex);
                OUT.worldPosition = v.vertex;
                OUT.vertex = vPosition;

                float2 pixelSize = vPosition.w;
                pixelSize /= float2(1, 1) * abs(mul((float2x2)UNITY_MATRIX_P, _ScreenParams.xy));

                float4 clampedRect = clamp(_ClipRect, -2e10, 2e10);
                float2 maskUV = (v.vertex.xy - clampedRect.xy) / (clampedRect.zw - clampedRect.xy);
                OUT.texcoord = TRANSFORM_TEX(v.texcoord.xy, _MainTex);
                OUT.mask = float4(v.vertex.xy * 2 - clampedRect.xy - clampedRect.zw, 0.25 / (0.25 * half2(_UIMaskSoftnessX, _UIMaskSoftnessY) + abs(pixelSize.xy)));


                if (_UIVertexColorAlwaysGammaSpace)
                {
                    if(!IsGammaSpace())
                    {
                        v.color.rgb = UIGammaToLinear(v.color.rgb);
                    }
                }

                OUT.color = v.color * _Color;
                return OUT;
            }

            // ガウスぼかし計算
            float gauss(float x, float y, float sigma)
            {
                return  1.0f / (2.0f * PI * sigma * sigma) * exp(-(x * x + y * y) / (2.0f * sigma * sigma));
            }

            // ガウスぼかし
            float4 frag(v2f IN) : COLOR
            {
                half4 color;
                float sum = 0;
                float2 uvOffset;
                float weight;
                int kernelSize = _KernelSize;

                // const half alphaPrecision = half(0xff);
                // const half invAlphaPrecision = half(1.0/alphaPrecision);
                // IN.color.a = round(IN.color.a * alphaPrecision)*invAlphaPrecision;

                for (int x = -kernelSize / 2; x <= kernelSize / 2; ++x)
                    for (int y = -kernelSize / 2; y <= kernelSize / 2; ++y)
                    {
                        //オフセットを計算する
                        uvOffset = IN.texcoord;
                        uvOffset.x += x * _MainTex_TexelSize.x;
                        uvOffset.y += y * _MainTex_TexelSize.y;
                        //重みを確認する
                        weight = gauss(x, y, _Sigma);

                        // 透明な部分は、暗くする（半透明部分が白くなる問題の対策）
                        half4 tmpcolor = tex2D(_MainTex, uvOffset);
                        tmpcolor.rgb *= tmpcolor.a;

                        color += tmpcolor * weight;
                        sum += weight;
                    }
                
                color *= (1.0f / sum);

                // #ifdef UNITY_UI_CLIP_RECT
                // half2 m = saturate((_ClipRect.zw - _ClipRect.xy - abs(IN.mask.xy)) * IN.mask.zw);
                // color.a *= m.x * m.y;
                // #endif

                // #ifdef UNITY_UI_ALPHACLIP
                // clip (color.a - 0.001);
                // #endif

                //color.a = tex2D(_MainTex, uvOffset).a;

                //color.a = 1.0;

                // 透明な部分は描画しない（白が映る対策）
                clip (color.a - 0.001);

                return color;
            }

            // fixed4 frag(v2f IN) : SV_Target
            // {
            //     //Round up the alpha color coming from the interpolator (to 1.0/256.0 steps)
            //     //The incoming alpha could have numerical instability, which makes it very sensible to
            //     //HDR color transparency blend, when it blends with the world's texture.
            //     const half alphaPrecision = half(0xff);
            //     const half invAlphaPrecision = half(1.0/alphaPrecision);
            //     IN.color.a = round(IN.color.a * alphaPrecision)*invAlphaPrecision;

            //     half4 color = IN.color * (tex2D(_MainTex, IN.texcoord) + _TextureSampleAdd);

            //     #ifdef UNITY_UI_CLIP_RECT
            //     half2 m = saturate((_ClipRect.zw - _ClipRect.xy - abs(IN.mask.xy)) * IN.mask.zw);
            //     color.a *= m.x * m.y;
            //     #endif

            //     #ifdef UNITY_UI_ALPHACLIP
            //     clip (color.a - 0.001);
            //     #endif

            //     color.rgb *= IN.color.a;

            //     return color;
            // }

        ENDCG
        }
    }
}
