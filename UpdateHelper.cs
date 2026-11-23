using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
internal static class FramewellUpdateHelper {
 [STAThread] static void Main(string[] args) {
  try {
   if(args.Length!=3)throw new ArgumentException("Invalid update handoff.");
   int pid=Int32.Parse(args[1]);long ticks=Int64.Parse(args[2]);
   try{using(var app=Process.GetProcessById(pid)){
    if(app.StartTime.ToUniversalTime().Ticks!=ticks)throw new InvalidOperationException("The original app process changed.");
    if(!app.WaitForExit(120000))throw new InvalidOperationException("Framewell is still open; the update was not applied.");
   }}catch(ArgumentException){}
   Framewell.Updates.Apply(args[0]);
  }catch(Exception error){
   try{File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"update-error.txt"),error.Message);}catch{}
   MessageBox.Show("The update was not completed. Personal profiles and settings were not changed.\n\n"+error.Message,"Framewell update",MessageBoxButtons.OK,MessageBoxIcon.Warning);
  }
 }
}
