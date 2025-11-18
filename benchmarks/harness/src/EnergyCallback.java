/*
 * Copyright (c) 2006, 2009 The Australian National University.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Apache License v2.0.
 * You may obtain the license at
 *
 *    http://www.opensource.org/licenses/apache2.0.php
 *
 * EnergyCallback:
 *   A DaCapo callback that uses jRAPL (EnergyCheckUtils) to measure
 *   the energy consumed by each benchmark iteration, together with
 *   the execution time reported by the harness.
 *
 * Example usage:
 *
 *   javac -cp . org/dacapo/harness/*.java org/dacapo/analysis/*.java EnergyCallback.java benchmarks/libs/jRAPL-master/EnergyCheckUtils.java
 *
 *   sudo java \
 *     -Ddacapo.energy.yml=energy.yml \
 *     -cp .:<dacapo_jar> \
 *     -jar <dacapo_version>.jar \
 *     -callback EnergyCallback \
 *     <benchmark>
 */

import java.io.File;
import java.io.PrintStream;

import org.dacapo.harness.Callback;
import org.dacapo.harness.CommandLineArgs;

/**
 * Callback to measure execution time and energy consumption of DaCapo
 * benchmarks using the jRAPL library (EnergyCheckUtils).
 *
 * The results are written as:
 *  - a small YAML-like report either to stdout or to the file specified by
 *    the system property "dacapo.energy.yml"; and
 *  - a CSV line appended to the file specified by "dacapo.energy.csv"
 *    (or "energy.csv" in the current directory by default).
 */
public class EnergyCallback extends Callback {

  /** System property that controls where the YAML report is written. */
  private static final String YML_FILENAME_PROPERTY = "dacapo.energy.yml";

  /** System property that controls where the CSV data is appended. */
  private static final String CSV_FILENAME_PROPERTY = "dacapo.energy.csv";

  /**
   * Used only to distinguish warmup iterations from the timing iteration
   * in the output filename (".0" for warmup, no suffix for timing), in
   * the same spirit as AllocCallback/BytecodeCallback.
   */
  private static int iteration = 0;
  private static String ymlSuffix = "";

  /** Energy readings taken immediately before/after each benchmark run. */
  private double[] energyBefore;
  private double[] energyAfter;

  public EnergyCallback(CommandLineArgs args) {
    super(args);
  }

  /* Immediately prior to start of the benchmark */
  @Override
  public void start(String benchmark) {
    // Take an initial energy snapshot using jRAPL
    try {
      energyBefore = EnergyCheckUtils.getEnergyStats();
    } catch (UnsatisfiedLinkError e) {
      System.err.println("EnergyCallback: failed to read energy counters (jRAPL native library not available): " + e);
      energyBefore = null;
    } catch (Throwable t) {
      System.err.println("EnergyCallback: unexpected error while reading initial energy stats: " + t);
      energyBefore = null;
    }

    super.start(benchmark);
  }

  /* Immediately after the end of the benchmark */
  @Override
  public void stop(long duration) {
    // First let the harness record the elapsed time
    super.stop(duration);

    // Capture the final energy snapshot for this iteration
    try {
      energyAfter = EnergyCheckUtils.getEnergyStats();
    } catch (UnsatisfiedLinkError e) {
      System.err.println("EnergyCallback: failed to read energy counters (jRAPL native library not available): " + e);
      energyAfter = null;
    } catch (Throwable t) {
      System.err.println("EnergyCallback: unexpected error while reading final energy stats: " + t);
      energyAfter = null;
    }

    // Use a suffix to distinguish warmup from the timing iteration
    ymlSuffix = isWarmup() ? ("." + iteration) : "";
  }

  @Override
  public void complete(String benchmark, boolean valid) {
    super.complete(benchmark, valid);
    report(benchmark, valid);
  }

  /**
   * Compute per-socket energy deltas and emit a simple YAML-style report
   * including both the time (in milliseconds) and energy (in joules).
   */
  private void report(String benchmark, boolean valid) {
    if (energyBefore == null || energyAfter == null) {
      System.err.println("EnergyCallback: energy measurements are unavailable for this iteration.");
      return;
    }

    PrintStream yml = System.out;

    String ymlfile = System.getProperty(YML_FILENAME_PROPERTY);
    if (ymlfile == null) {
      System.out.println("The '" + YML_FILENAME_PROPERTY + "' system property is not set, so printing energy yml to console.");
    } else {
      ymlfile += ymlSuffix;
      try {
        yml = new PrintStream(new File(ymlfile));
      } catch (Exception e) {
        System.err.println("Could not open '" + ymlfile + "', so printing energy yml to console.");
        yml = System.out;
      }
    }

    int socketNum = EnergyCheckUtils.socketNum;
    if (socketNum <= 0) {
      // Fallback: infer sockets from the returned array length
      socketNum = energyBefore.length / 3;
    }

    if (socketNum <= 0 || energyBefore.length < 3 * socketNum || energyAfter.length < 3 * socketNum) {
      System.err.println("EnergyCallback: inconsistent energy vector sizes; skipping report.");
      return;
    }

    // Header and metadata
    yml.println("# Energy statistics generated from a DaCapo run using jRAPL");
    yml.println("# Example:");
    yml.println("#   sudo java -D" + YML_FILENAME_PROPERTY + "=<output_file> -jar <dacapo_version>.jar -callback EnergyCallback <benchmark>");
    yml.println("#");
    yml.println("benchmark: " + benchmark);
    yml.println("valid: " + valid);
    yml.println("warmup: " + isWarmup());
    yml.println("elapsed-time-ms: " + elapsed);
    yml.println("sockets: " + socketNum);
    yml.println("energy-joules:");

    for (int s = 0; s < socketNum; s++) {
      int base = s * 3;

      double dramBefore = energyBefore[base];
      double cpuBefore = energyBefore[base + 1];
      double pkgBefore = energyBefore[base + 2];

      double dramAfter = energyAfter[base];
      double cpuAfter = energyAfter[base + 1];
      double pkgAfter = energyAfter[base + 2];

      double dramDelta = deltaWithWraparound(dramAfter, dramBefore);
      double cpuDelta = deltaWithWraparound(cpuAfter, cpuBefore);
      double pkgDelta = deltaWithWraparound(pkgAfter, pkgBefore);

      yml.println("  socket-" + s + ":");
      yml.println("    dram: " + dramDelta);
      yml.println("    cpu: " + cpuDelta);
      yml.println("    package: " + pkgDelta);

      // Append the same information to a CSV file (one line per socket).
      appendCsvRow(benchmark, valid, isWarmup(), elapsed, s, dramDelta, cpuDelta, pkgDelta);
    }

    if (yml != System.out) {
      try {
        yml.close();
      } catch (Exception e) {
        System.err.println("EnergyCallback: exception closing file: " + e);
      }
    }
  }

  /**
   * Append a single CSV row with the energy information for one socket.
   * The file is created on first use and a header row is written once.
   */
  private void appendCsvRow(String benchmark, boolean valid, boolean warmup,
                            long elapsedMs, int socketId,
                            double dramJ, double cpuJ, double pkgJ) {
    String csvFileName = System.getProperty(CSV_FILENAME_PROPERTY, "energy.csv");
    File csvFile = new File(csvFileName);
    boolean newFile = !csvFile.exists();

    PrintStream csv = null;
    try {
      csv = new PrintStream(new java.io.FileOutputStream(csvFile, true));

      if (newFile) {
        csv.println("benchmark,valid,warmup,elapsed_ms,socket,dram_j,cpu_j,package_j");
      }

      csv.printf("%s,%b,%b,%d,%d,%.9f,%.9f,%.9f%n",
                 benchmark, valid, warmup, elapsedMs, socketId,
                 dramJ, cpuJ, pkgJ);
    } catch (Exception e) {
      System.err.println("EnergyCallback: could not append to CSV '" + csvFileName + "': " + e);
    } finally {
      if (csv != null) {
        try {
          csv.close();
        } catch (Exception ignore) {
        }
      }
    }
  }

  /**
   * Compute the delta between two energy readings, compensating for
   * possible wraparound of the underlying hardware counter.
   */
  private double deltaWithWraparound(double after, double before) {
    double d = after - before;
    if (d < 0) {
      // Counter wrapped; compensate using the wraparound value exposed by jRAPL.
      d += EnergyCheckUtils.wraparoundValue;
    }
    return d;
  }
}


