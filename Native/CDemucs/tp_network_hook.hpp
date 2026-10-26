// TonePilot: lets the Demucs network core run elsewhere (Core ML on the GPU / Neural Engine).
#pragma once
namespace demucscpp { struct demucs_segment_buffers; }
namespace tp {
/// Runs the network between input normalisation and de-normalisation for one segment, filling
/// buffers.x_out and buffers.xt_out. Returns false when no external network is set (the
/// original CPU code then runs).
bool run_network(demucscpp::demucs_segment_buffers &buffers, int nb_sources);
}
