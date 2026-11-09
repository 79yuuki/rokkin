// Rokkin neon flow — shared by the landing page and the explainer video.
// Usage: const fx = RokkinShader(canvas, {preserve:true}); fx.draw(timeSec, {energy, beat, mouse:[x,y]})
(function (root) {
  const VERT = 'attribute vec2 a; void main(){ gl_Position = vec4(a,0.0,1.0); }';
  const FRAG = `
precision highp float;
uniform vec2 uRes; uniform float uTime; uniform vec2 uMouse; uniform float uEnergy; uniform float uBeat; uniform float uGrain;
vec2 hash(vec2 p){ p=vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))); return -1.0+2.0*fract(sin(p)*43758.5453123); }
float noise(vec2 p){
  const float K1=0.366025404; const float K2=0.211324865;
  vec2 i=floor(p+(p.x+p.y)*K1); vec2 a=p-i+(i.x+i.y)*K2;
  float m=step(a.y,a.x); vec2 o=vec2(m,1.0-m);
  vec2 b=a-o+K2; vec2 c=a-1.0+2.0*K2;
  vec3 h=max(0.5-vec3(dot(a,a),dot(b,b),dot(c,c)),0.0);
  vec3 n=h*h*h*h*vec3(dot(a,hash(i)),dot(b,hash(i+o)),dot(c,hash(i+1.0)));
  return dot(n,vec3(70.0));
}
float fbm(vec2 p){ float f=0.0, a=0.5; mat2 r=mat2(1.6,1.2,-1.2,1.6); for(int i=0;i<4;i++){ f+=a*noise(p); p=r*p; a*=0.5; } return f; }
void main(){
  vec2 uv = gl_FragCoord.xy / uRes.xy;
  vec2 p = (gl_FragCoord.xy - 0.5*uRes.xy) / uRes.y;
  float t = uTime*0.06;
  vec2 q = vec2(fbm(p*0.75 + vec2(0.0, t)), fbm(p*0.75 + vec2(5.2, -t*0.8)));
  vec2 r = vec2(fbm(p*0.85 + 1.4*q + vec2(1.7,9.2) + t*1.2), fbm(p*0.85 + 1.4*q + vec2(8.3,2.8) - t));
  float f = fbm(p*0.7 + 1.5*r);
  vec3 base   = vec3(0.022,0.012,0.065);
  vec3 pink   = vec3(1.00,0.23,0.62);
  vec3 violet = vec3(0.48,0.17,1.00);
  vec3 cyan   = vec3(0.09,0.78,1.00);
  vec3 col = base;
  col = mix(col, violet*0.85, smoothstep(-0.35, 0.55, f) * 0.85);
  col = mix(col, pink,   smoothstep(0.05, 0.75, r.x + f*0.35) * 0.80);
  col = mix(col, cyan,   smoothstep(0.15, 0.85, q.y + r.y*0.35) * 0.70);
  float ribbon = abs(fract(f*2.2 + r.y*0.8 + uTime*0.03) - 0.5);
  col += smoothstep(0.035, 0.0, ribbon) * 0.10 * mix(pink, cyan, uv.x);
  col *= (0.40 + 0.50*uEnergy) * (1.0 + 0.10*uBeat);
  float md = length(p - uMouse);
  col += 0.10*exp(-md*3.2)*vec3(1.0,0.55,1.0);
  col *= smoothstep(1.35, 0.25, length(uv-0.5)*1.45);
  float g = fract(sin(dot(gl_FragCoord.xy + fract(uTime)*91.0, vec2(12.9898,78.233)))*43758.5453);
  col += (g-0.5)*uGrain;
  gl_FragColor = vec4(col, 1.0);
}`;
  function RokkinShader(canvas, opts) {
    opts = opts || {};
    const gl = canvas.getContext('webgl', { preserveDrawingBuffer: !!opts.preserve, antialias: false, alpha: false });
    if (!gl) return null;
    function sh(type, src) {
      const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    }
    const pr = gl.createProgram();
    gl.attachShader(pr, sh(gl.VERTEX_SHADER, VERT));
    gl.attachShader(pr, sh(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(pr);
    gl.useProgram(pr);
    const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(pr, 'a');
    gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    const U = n => gl.getUniformLocation(pr, n);
    const uRes = U('uRes'), uTime = U('uTime'), uMouse = U('uMouse'), uEnergy = U('uEnergy'), uBeat = U('uBeat'), uGrain = U('uGrain');
    return {
      draw(t, o) {
        o = o || {};
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.uniform2f(uRes, canvas.width, canvas.height);
        gl.uniform1f(uTime, t);
        const m = o.mouse || [0.0, 0.0];
        gl.uniform2f(uMouse, m[0], m[1]);
        gl.uniform1f(uEnergy, o.energy == null ? 1.0 : o.energy);
        gl.uniform1f(uBeat, o.beat || 0.0);
        gl.uniform1f(uGrain, o.grain == null ? 0.028 : o.grain);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }
    };
  }
  root.RokkinShader = RokkinShader;
})(window);
