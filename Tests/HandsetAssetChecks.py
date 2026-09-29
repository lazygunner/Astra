"""Compare source and prepared USDZ geometry. Requires usd-core; pass both paths."""
import sys
from collections import Counter
from pxr import Usd,UsdGeom,UsdShade

def faces(path):
 s=Usd.Stage.Open(path); cache=UsdGeom.XformCache(); result=Counter(); total=0
 for p in s.Traverse():
  if not p.IsA(UsdGeom.Mesh):continue
  m=UsdGeom.Mesh(p); pts=m.GetPointsAttr().Get(); inds=m.GetFaceVertexIndicesAttr().Get(); counts=m.GetFaceVertexCountsAttr().Get()
  transform=cache.GetLocalToWorldTransform(p)
  world=[tuple(round(v,5) for v in transform.Transform(pt)) for pt in pts]
  material=str(UsdShade.MaterialBindingAPI(p).ComputeBoundMaterial()[0].GetPath())
  normals=m.GetNormalsAttr().Get(); uv=UsdGeom.PrimvarsAPI(p).GetPrimvar('st'); flattened=uv.ComputeFlattened() if uv else None
  offset=0
  for count in counts:
   corners=range(offset,offset+count)
   key=(material,tuple(world[inds[c]] for c in corners),tuple(tuple(normals[c]) for c in corners) if normals else None,tuple(tuple(flattened[c]) for c in corners) if flattened else None)
   result[key]+=1;total+=1;offset+=count
 return result,total
before,n=faces(sys.argv[1])
after,m=faces(sys.argv[2])
assert n==m,(n,m)
assert before==after,(sum((before-after).values()),sum((after-before).values()))
print(f'PASS: {n} faces preserved with identical materials, normals, UVs and world positions (10 μm tolerance).')
