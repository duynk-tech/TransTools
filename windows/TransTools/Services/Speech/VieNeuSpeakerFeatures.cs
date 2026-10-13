namespace TransTools.Services.Speech;

// Matches the current macOS Kaldi-style front end; input is 16 kHz mono.
public static class VieNeuSpeakerFeatures
{
    public static float[] Extract(float[] samples, CancellationToken token = default)
    {
        if (samples.Length < 48000 || samples.Length > 128000 || samples.Any(value => !float.IsFinite(value)))
            throw new ArgumentException("Bản thu cần từ 3 đến 8 giây, âm thanh hợp lệ.");
        int frames = (samples.Length - 400) / 160 + 1;
        var result = new float[frames * 80];
        var weights = new float[80,256];
        double Mel(double frequency) => 1127 * Math.Log(1 + frequency / 700);
        double low = Mel(20), step = (Mel(8000) - low) / 81;
        for (int bin = 0; bin < 80; bin++) for (int k = 0; k < 256; k++) {
            double m = Mel(k * 16000.0 / 512), left = low + bin * step;
            weights[bin,k] = (float)Math.Max(0,Math.Min((m-left)/step,(left+2*step-m)/step));
        }
        var window = Enumerable.Range(0,400).Select(i => (float)Math.Pow(.5-.5*Math.Cos(2*Math.PI*i/399),.85)).ToArray();
        var real = new float[512]; var imaginary = new float[512];
        for (int frame = 0; frame < frames; frame++) {
            token.ThrowIfCancellationRequested();
            int offset = frame * 160; float mean = 0;
            for (int i=0;i<400;i++) mean += samples[offset+i];
            mean /= 400;
            Array.Clear(real); Array.Clear(imaginary);
            for (int i=0;i<400;i++) real[i] = ((samples[offset+i]-mean)-.97f*(samples[offset+Math.Max(0,i-1)]-mean))*window[i];
            Fft(real,imaginary);
            for (int bin=0;bin<80;bin++) {
                float energy=0;
                for (int k=0;k<256;k++) energy += (real[k]*real[k]+imaginary[k]*imaginary[k])*weights[bin,k];
                result[frame*80+bin]=MathF.Log(Math.Max(1.1920929e-7f,energy));
            }
        }
        for (int bin=0;bin<80;bin++) {
            float mean=0; for(int frame=0;frame<frames;frame++) mean+=result[frame*80+bin];
            mean/=frames; for(int frame=0;frame<frames;frame++) result[frame*80+bin]-=mean;
        }
        return result;
    }
    private static void Fft(float[] real,float[] imaginary)
    {
        for(int i=1,j=0;i<512;i++) {
            int bit=256; for(; (j&bit)!=0;bit>>=1) j^=bit; j^=bit;
            if(i<j) { (real[i],real[j])=(real[j],real[i]); (imaginary[i],imaginary[j])=(imaginary[j],imaginary[i]); }
        }
        for(int length=2;length<=512;length<<=1) {
            int half=length/2;
            for(int start=0;start<512;start+=length) for(int k=0;k<half;k++) {
                float c=(float)Math.Cos(-2*Math.PI*k/length), s=(float)Math.Sin(-2*Math.PI*k/length);
                int a=start+k,b=a+half;
                float r=c*real[b]-s*imaginary[b], im=s*real[b]+c*imaginary[b];
                real[b]=real[a]-r; imaginary[b]=imaginary[a]-im; real[a]+=r; imaginary[a]+=im;
            }
        }
    }
}
