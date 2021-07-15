using System.Collections.Concurrent;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Npgsql;

namespace listener
{
    class Program
    {       
        static void Main()
        {
            var connstr = "Host=...;Username=...;Password=...;Database=musicstreamer"; //FIX ME
            var conn = new NpgsqlConnection(connstr);
            BlockingCollection<string> messageQueue = new();

            conn.Open();
            conn.Notification += (o, e) => 
            {
                messageQueue.Add(e.Payload);       
            };

            Task.Run(() => { //background task
                while (true)
                {
                    var msg = messageQueue.Take();
                    var obj = JObject.Parse(msg);
                    using var conn2 = new NpgsqlConnection(connstr);
                    conn2.Open();
                    
                    using (var cmd = new NpgsqlCommand("SELECT update_play_counts(@t, @u)", conn2))
                    { 
                        cmd.Parameters.AddWithValue("t", obj["track_id"].ToObject<int>());
                        cmd.Parameters.AddWithValue("u", obj["user_id"].ToObject<int>());
                        cmd.ExecuteNonQuery();
                    }
                    conn2.Close();
                }      
            });

            using (var cmd = new NpgsqlCommand("LISTEN play_history_insert", conn)) {
                cmd.ExecuteNonQuery();
            }

            while (true) {
                conn.Wait(); //blocking
            }
        }
    }
}
