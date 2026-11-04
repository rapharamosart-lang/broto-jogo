# blender -b /workspace/rig/rig2.blend -P tools/export_rig.py -- out.glb
import bpy,sys
out=sys.argv[sys.argv.index('--')+1]
print('ACTIONS',[a.name for a in bpy.data.actions])
bpy.ops.export_scene.gltf(filepath=out,export_format='GLB',export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_apply=False,export_yup=True)
