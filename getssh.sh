#!/bin/bash
echo "compiling ssh [TF2]"
/home/steph/tfTEST/tf2/tf/addons/sourcemod/scripting/spcomp \
-i./scripting/include \
./scripting/supersprayhandler.sp \
-o /home/steph/tfTEST/tf2/tf/addons/sourcemod/plugins/ssh.smx
sync; sleep 1
echo ""




echo "compiling ssh [TF2 1.10]"
/home/steph/tfTEST/tf2/tf/addons_1.10/sourcemod/scripting/spcomp \
-i./scripting/include \
./scripting/supersprayhandler.sp \
-o ./plugins/ssh.smx
sync; sleep 1
echo ""
