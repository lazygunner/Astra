#!/usr/bin/env python3
"""Split the authored telephone by connected components. Requires usd-core.

Usage: python prepare_handset.py source.usdz output.usdz
Input and output must differ. The original materials, UVs and other scene objects
are preserved. Component bounds below are in the source's Z-up mesh coordinates.
"""
import argparse
from pathlib import Path
import tempfile
import zipfile
from pxr import Gf, Sdf, Usd, UsdGeom, UsdUtils, Vt


def components(mesh):
    points = mesh.GetPointsAttr().Get()
    counts = list(mesh.GetFaceVertexCountsAttr().Get())
    indices = list(mesh.GetFaceVertexIndicesAttr().Get())
    parents = list(range(len(points)))

    def root(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    offset = 0
    faces = []
    for count in counts:
        face = indices[offset:offset + count]
        faces.append(face)
        for i in face:
            parents[root(i)] = root(face[0])
        offset += count
    groups = {}
    for index, face in enumerate(faces):
        groups.setdefault(root(face[0]), []).append(index)
    return points, faces, list(groups.values())


def filter_faces(mesh, selected):
    """Keep whole faces, remapping vertices, normals and indexed face-varying UVs."""
    points, faces, _ = components(mesh)
    counts = mesh.GetFaceVertexCountsAttr().Get()
    offsets = [0]
    for count in counts:
        offsets.append(offsets[-1] + count)
    corners = [c for f in selected for c in range(offsets[f], offsets[f + 1])]
    vertices = sorted({v for f in selected for v in faces[f]})
    remap = {old: new for new, old in enumerate(vertices)}
    new_points = Vt.Vec3fArray([points[v] for v in vertices])
    # This asset has only face-varying normals and indexed face-varying UVs.
    assert mesh.GetNormalsInterpolation() == UsdGeom.Tokens.faceVarying
    normals = mesh.GetNormalsAttr().Get()
    mesh.GetNormalsAttr().Set(Vt.Vec3fArray([normals[c] for c in corners]))
    for pv in UsdGeom.PrimvarsAPI(mesh).GetPrimvars():
        if not pv.HasValue():
            continue
        assert pv.GetInterpolation() == UsdGeom.Tokens.faceVarying, pv.GetName()
        assert pv.IsIndexed(), pv.GetName()
        old = pv.GetIndices()
        pv.SetIndices(Vt.IntArray([old[c] for c in corners]))
    mesh.GetPointsAttr().Set(new_points)
    mesh.GetFaceVertexCountsAttr().Set(Vt.IntArray([len(faces[f]) for f in selected]))
    mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray([remap[v] for f in selected for v in faces[f]]))
    mesh.GetExtentAttr().Set(UsdGeom.PointBased.ComputeExtent(new_points))


def prepare(source, output):
    assert source.resolve() != output.resolve(), 'Keep the source asset as a backup.'
    with tempfile.TemporaryDirectory(prefix='astra-handset-') as work:
        with zipfile.ZipFile(source) as package:
            root_file = package.namelist()[0]
            package.extractall(work)
        stage = Usd.Stage.Open(str(Path(work) / root_file))
        assert not stage.GetPrimAtPath('/HotlineGlassCube/AstraTelephoneHandset')
        group = UsdGeom.Xform.Define(stage, '/HotlineGlassCube/AstraTelephoneHandset')
        # Put the manipulation pivot at the handle, not at the room origin.
        pivot = Gf.Vec3d(0.925, 0.184, 1.006)
        group.AddTranslateOp().Set(pivot)
        total_moved = 0
        for prim in list(stage.Traverse()):
            if not prim.IsA(UsdGeom.Mesh) or '_06_ReferenceHotline_' not in str(prim.GetPath()):
                continue
            mesh = UsdGeom.Mesh(prim)
            points, faces, groups = components(mesh)
            selected = []
            material = prim.GetParent().GetName()
            for group_faces in groups:
                ids = {v for f in group_faces for v in faces[f]}
                low = min(points[v][2] for v in ids)
                high = max(points[v][2] for v in ids)
                take = (
                    (material.endswith('_Hotline_Red_Polished_Bakelite') and low > 0.975)
                    or (material.endswith('_Red_Bakelite_Mould_Seam') and low > 0.975)
                    or (material.endswith('_Rubber_And_Recesses') and 0.967 < low < 0.969 and high < 0.975)
                    or material.endswith('_Dark_Anodised_Frame')
                )
                if take:
                    selected.extend(group_faces)
            if not selected:
                continue
            selected.sort()
            mesh_name = prim.GetName()
            destination = group.GetPath().AppendChild(mesh_name)
            assert Sdf.CopySpec(stage.GetRootLayer(), prim.GetPath(), stage.GetRootLayer(), destination)
            moving = UsdGeom.Mesh(stage.GetPrimAtPath(destination))
            filter_faces(moving, selected)
            UsdGeom.Xformable(moving).AddTranslateOp().Set(-pivot)
            remaining = sorted(set(range(len(faces))) - set(selected))
            assert len(selected) + len(remaining) == len(faces)
            if remaining:
                filter_faces(mesh, remaining)
            else:
                stage.RemovePrim(prim.GetPath())
            total_moved += len(selected)
            print(f'{mesh_name}: {len(selected)} handset faces, {len(remaining)} stationary faces')
        assert len(group.GetPrim().GetChildren()) == 4
        assert total_moved == 19876, f"Unexpected source geometry: {total_moved} handset faces"
        stage.GetRootLayer().Save()
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(Path(work) / root_file)), str(output.resolve()))
        # Open the final package and verify all authored meshes and texture references.
        final = Usd.Stage.Open(str(output.resolve()))
        assert final.GetPrimAtPath('/HotlineGlassCube/AstraTelephoneHandset')
        _, _, unresolved = UsdUtils.ComputeAllDependencies(str(output.resolve()))
        assert not unresolved, unresolved
        print(f'Wrote {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    prepare(args.source, args.output)
