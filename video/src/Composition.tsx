import React from "react";
import {
  AbsoluteFill,
  Composition,
  Img,
  Sequence,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";

const FPS = 30;
const PAPER = "#f3f0e8";
const INK = "#211f1a";
const GREEN = "#3c5a45";

const FadeIn: React.FC<{ children: React.ReactNode; start?: number }> = ({
  children,
  start = 0,
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame - start, [0, 12], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const y = interpolate(frame - start, [0, 18], [18, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <div
      style={{
        position: "absolute",
        inset: 0,
        opacity,
        transform: `translateY(${y}px)`,
      }}
    >
      {children}
    </div>
  );
};

const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const scale = interpolate(frame, [0, 100], [1.04, 1], {
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill style={{ backgroundColor: PAPER, color: INK }}>
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(ellipse at 78% 24%, rgba(60,90,69,.13), transparent 38%), linear-gradient(130deg, #f3f0e8 0%, #e9e5d9 100%)",
        }}
      />
      <FadeIn start={12}>
        <div style={{ position: "absolute", left: 110, top: 250, width: 900, color: INK }}>
          <div style={{ color: GREEN, fontSize: 23, fontWeight: 700, letterSpacing: 2, marginBottom: 28 }}>PRECIS FOR MAC</div>
          <div style={{ fontFamily: "Georgia, 'Times New Roman', serif", fontWeight: 700, fontSize: 78, lineHeight: 1.04, letterSpacing: -2.2, maxWidth: 850 }}>
            A clearer way to keep up.
          </div>
          <div style={{ marginTop: 28, maxWidth: 760, fontSize: 29, lineHeight: 1.4, color: "#55564f" }}>
            Your feeds, your stories, and your daily précis—together on your Mac.
          </div>
          <div style={{ marginTop: 48, paddingTop: 22, width: 760, borderTop: "1px solid #c9c2b2", color: GREEN, fontSize: 18, fontWeight: 700, letterSpacing: 1.1 }}>
            READ AT YOUR PACE&nbsp;&nbsp; · &nbsp;&nbsp;KEEP WHAT MATTERS CLOSE
          </div>
        </div>
      </FadeIn>
      <Img
        src={staticFile("assets/app-icon.png")}
        style={{
          position: "absolute",
          right: 220,
          top: 190,
          width: 360,
          height: 360,
          borderRadius: 82,
          transform: `scale(${scale})`,
          boxShadow: "0 42px 100px rgba(32,38,30,.19)",
        }}
      />
      <div style={{ position: "absolute", right: 285, top: 610, color: "#7c7b70", fontSize: 18, letterSpacing: 3 }}>
        A MAC READING DESK
      </div>
    </AbsoluteFill>
  );
};

const DesktopPanel: React.FC = () => {
  const frame = useCurrentFrame();
  const scale = interpolate(frame, [0, 180], [1, 1.035], {
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill style={{ backgroundColor: "#142027" }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "radial-gradient(ellipse at 20% 85%, #34544c 0%, transparent 42%), linear-gradient(120deg, #13242a 0%, #203a3b 60%, #0d1920 100%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          right: 150,
          top: 16,
          width: 330,
          height: 1048,
          borderRadius: 20,
          overflow: "hidden",
          border: "1px solid rgba(255,255,255,.18)",
          boxShadow: "0 30px 90px rgba(0,0,0,.45)",
          transform: `scale(${scale})`,
        }}
      >
        <Img
          src={staticFile("assets/desktop-capture.png")}
          style={{ width: "100%", height: "100%", objectFit: "contain" }}
        />
      </div>
      <FadeIn start={14}>
        <div style={{ position: "absolute", left: 108, top: 225, width: 1120, color: "#fffdf7" }}>
          <div style={{ fontSize: 21, fontWeight: 700, letterSpacing: 1.8, color: "#c1d2c4", marginBottom: 30 }}>YOUR DESKTOP COMPANION</div>
          <div style={{ fontFamily: "Georgia, 'Times New Roman', serif", fontWeight: 700, fontSize: 78, lineHeight: 1.03, letterSpacing: -1.8, maxWidth: 1000 }}>
            Your reading, right where you need it.
          </div>
          <div style={{ marginTop: 28, maxWidth: 850, fontSize: 29, lineHeight: 1.38, color: "rgba(255,253,247,.82)" }}>
            A discreet, configurable panel keeps recent stories from your chosen feeds within reach while you work.
          </div>
          <div style={{ marginTop: 46, paddingTop: 22, width: 820, borderTop: "1px solid rgba(255,253,247,.36)", display: "flex", gap: 48, color: "#e3e9df", fontSize: 19, fontWeight: 650, letterSpacing: 0.5 }}>
            <span>RECENT FEEDS</span><span>YOUR LIST</span><span>AT A GLANCE</span>
          </div>
        </div>
      </FadeIn>
    </AbsoluteFill>
  );
};

const Newspaper: React.FC = () => {
  const frame = useCurrentFrame();
  const scale = interpolate(frame, [0, 210], [0.91, 1], {
    extrapolateRight: "clamp",
  });
  const opacity = interpolate(frame, [0, 16], [0, 1], {
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill style={{ backgroundColor: "#ded9cc" }}>
      <AbsoluteFill style={{ background: "linear-gradient(115deg, #ebe7dd 0%, #d8d1c3 100%)" }} />
      <div
        style={{
          position: "absolute",
          left: 195,
          top: 174,
          width: 620,
          color: INK,
        }}
      >
        <div style={{ color: GREEN, fontSize: 21, fontWeight: 700, letterSpacing: 1.5, marginBottom: 30 }}>
          MADE FOR THE STORIES YOU CHOOSE
        </div>
        <div style={{ fontFamily: "Georgia, 'Times New Roman', serif", fontSize: 68, fontWeight: 700, lineHeight: 1.06, letterSpacing: -1.5 }}>
          Bring your own edition to life.
        </div>
        <div style={{ marginTop: 28, fontSize: 28, lineHeight: 1.42, color: "#56564f", maxWidth: 570 }}>
          Gather selected articles into a newspaper-style PDF, ready to read or share.
        </div>
        <div style={{ marginTop: 48, paddingTop: 20, borderTop: "1px solid #c9c2b2", color: GREEN, fontSize: 18, fontWeight: 700, letterSpacing: 1 }}>
          SELECT&nbsp;&nbsp; · &nbsp;&nbsp;GATHER&nbsp;&nbsp; · &nbsp;&nbsp;SAVE AS PDF
        </div>
      </div>
      <Img
        src={staticFile("assets/newspaper.png")}
        style={{
          position: "absolute",
          width: 740,
          height: 960,
          right: 175,
          top: 60,
          objectFit: "contain",
          opacity,
          transform: `scale(${scale}) rotate(1deg)`,
          boxShadow: "0 30px 60px rgba(27,25,19,.25)",
        }}
      />
    </AbsoluteFill>
  );
};

const DailyDigest: React.FC = () => {
  const frame = useCurrentFrame();
  const scale = interpolate(frame, [0, 210], [1.06, 1], {
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill style={{ backgroundColor: PAPER }}>
      <div style={{ position: "absolute", inset: 0, background: "linear-gradient(115deg, #f3f0e8 0%, #e9e5d9 100%)" }} />
      <div style={{ position: "absolute", left: 82, top: 210, width: 470 }}>
        <div style={{ color: GREEN, fontSize: 21, fontWeight: 700, letterSpacing: 1.5, marginBottom: 30 }}>
          THE DAY, MADE CLEARER
        </div>
        <div style={{ fontFamily: "Georgia, 'Times New Roman', serif", fontSize: 66, fontWeight: 700, lineHeight: 1.04, letterSpacing: -1.5, color: INK }}>
          Get the day’s stories at a glance.
        </div>
        <div style={{ marginTop: 30, fontSize: 28, lineHeight: 1.42, color: "#56564f" }}>
          Precis brings your feeds together with a concise daily summary, so you can see the day’s main themes at a glance.
        </div>
        <div style={{ marginTop: 44, paddingTop: 21, borderTop: "1px solid #c9c2b2", color: GREEN, fontSize: 18, fontWeight: 700, letterSpacing: 1 }}>
          YOUR SOURCES&nbsp;&nbsp; · &nbsp;&nbsp;ONE DAILY PRÉCIS
        </div>
      </div>
      <div
        style={{
          position: "absolute",
          right: 70,
          top: 98,
          width: 1250,
          height: 885,
          overflow: "hidden",
          borderRadius: 22,
          boxShadow: "0 32px 76px rgba(32,38,30,.17)",
          border: "1px solid #d9d3c6",
          transform: `scale(${scale})`,
        }}
      >
        <Img src={staticFile("assets/reader.png")} style={{ width: "100%", height: "100%", objectFit: "cover", objectPosition: "center" }} />
      </div>
    </AbsoluteFill>
  );
};

const EndCard: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: GREEN, color: "#fffdf7", justifyContent: "center", alignItems: "center" }}>
    <Img src={staticFile("assets/app-icon.png")} style={{ width: 190, height: 190, borderRadius: 46, boxShadow: "0 25px 70px rgba(0,0,0,.24)" }} />
    <div style={{ fontFamily: "Georgia, 'Times New Roman', serif", fontSize: 92, fontWeight: 700, marginTop: 34 }}>
      Precis
    </div>
    <div style={{ marginTop: 22, fontSize: 31, color: "rgba(255,253,247,.9)" }}>
      A clearer way to keep up.
    </div>
    <div style={{ marginTop: 54, padding: "16px 28px", border: "1px solid rgba(255,253,247,.58)", borderRadius: 999, fontSize: 24, letterSpacing: 0.4 }}>
      Coming soon to the Mac App Store
    </div>
  </AbsoluteFill>
);

const Promo: React.FC = () => (
  <AbsoluteFill style={{ fontFamily: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif" }}>
    <Sequence from={0} durationInFrames={90}><Intro /></Sequence>
    <Sequence from={90} durationInFrames={210}><DesktopPanel /></Sequence>
    <Sequence from={300} durationInFrames={240}><Newspaper /></Sequence>
    <Sequence from={540} durationInFrames={210}><DailyDigest /></Sequence>
    <Sequence from={750} durationInFrames={150}><EndCard /></Sequence>
  </AbsoluteFill>
);

export const MyComposition = () => (
  <Composition
    id="PrecisPromo"
    component={Promo}
    durationInFrames={900}
    fps={FPS}
    width={1920}
    height={1080}
  />
);
