#!/bin/bash
echo "compiling ssh [TF2]"
/home/steph/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp \
-i./scripting/include \
./scripting/supersprayhandler.sp \
-o /home/steph/tfTEST/tf2/tf/addons/sourcemod/plugins/supersprayhandler.smx
sync; sleep 1
echo ""

sync

echo "compiling ssh [TF2 1.10]"
/home/steph/tfTEST/tf2/tf/addons_1.10/sourcemod/scripting/spcomp \
-i./scripting/include \
./scripting/supersprayhandler.sp \
-o ./plugins/supersprayhandler.smx
sync; sleep 1
echo ""
