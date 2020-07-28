version 1.0

workflow Parliament2 {
    input {
        File inputBam
        File inputBai
        File refFasta 
        File refIndex
        Boolean filterContigs
        Boolean runBreakdancer
        Boolean runBreakseq
        Boolean runCNVnator
        Boolean runDelly
        Boolean runLumpy
        Boolean runManta
    }

    # if (runBreakdancer || runCNVnator || runDelly || runManta) {
    #     call P2Prep {
    #         input:
    #             inputBam = inputBam,
    #             filterContigs = filterContigs
    #     }

    #     Array[String] chromosomes = read_lines(P2Prep.contigs)

    #     if (runBreakdancer) {
    #         call PrepareBreakdancer {
    #             input:
    #                 inputBam = inputBam
    #         }

    #         scatter (chromosome in chromosomes) {
    #             call BreakdancerChrom {
    #                 input:
    #                     inputBam = inputBam,
    #                     inputBai = inputBai,
    #                     refFasta = refFasta,
    #                     refIndex = refIndex,
    #                     configFile = PrepareBreakdancer.configFile,
    #                     contig = chromosome
    #             }
    #         }

    #         call GatherBreakdancer {
    #             input:
    #                 breakdancerCtx = BreakdancerChrom.breakdancerOutput,
    #                 bamBase = P2Prep.bamBase
    #         }
    #     }
        
    #     if (runCNVnator) {
    #         scatter (chromosome in chromosomes) {
    #             call CNVnatorChrom {
    #                 input:
    #                     inputBam = inputBam,
    #                     inputBai = inputBai,
    #                     refFasta = refFasta,
    #                     refIndex = refIndex,
    #                     contig = chromosome
    #             }
    #         }

    #         call GatherCNVnator {
    #             input:
    #                 CNVnatorCalls = CNVnatorChrom.CNVnatorOutput,
    #                 bamBase = P2Prep.bamBase
    #         }
    #     }

    #     if (runDelly) {
    #         scatter (chromosome in chromosomes) {
    #             call SplitByChrom {
    #                 input:
    #                     inputBam = inputBam,
    #                     inputBai = inputBai,
    #                     contig = chromosome
    #             }
    #             call DellyChrom {
    #                 input:
    #                     inputBam = SplitByChrom.splitBam,
    #                     inputBai = SplitByChrom.splitBai,
    #                     refFasta = refFasta,
    #                     refIndex = refIndex,
    #                     contig = chromosome
    #             }
    #         }

    #         call GatherDelly {
    #             input:
    #                 dellyDelVCFs = DellyChrom.dellyDeletion,
    #                 dellyDupVCFs = DellyChrom.dellyDuplication,
    #                 dellyInsVCFs = DellyChrom.dellyInsertion,
    #                 dellyInvVCFs = DellyChrom.dellyInversion,
    #                 bamBase = P2Prep.bamBase
    #         }
    #     }

    #     if (runManta) {
    #         call Manta {
    #             input:
    #                 inputBam = inputBam,
    #                 inputBai = inputBai,
    #                 refFasta = refFasta,
    #                 refIndex = refIndex,
    #                 contigs = P2Prep.contigs
    #         }
    #     }
    # }

    # if (runBreakseq) {
    #     call Breakseq { 
    #         input: 
    #             inputBam = inputBam,
    #             inputBai = inputBai,
    #             refFasta = refFasta,
    #             refIndex = refIndex
    #     }
    # }

    if (runLumpy) {
        call P2Prep {
            input:
                inputBam = inputBam,
                filterContigs = filterContigs
        }
        Array[String] chromosomes = read_lines(P2Prep.contigs)

        scatter (chromosome in chromosomes) {
            call SplitByChrom {
                input:
                    inputBam = inputBam,
                    inputBai = inputBai,
                    contig = chromosome
            }
            call LumpyChrom {
                input:
                    inputBam = SplitByChrom.splitBam,
                    inputBai = SplitByChrom.splitBai,
                    refFasta = refFasta,
                    refIndex = refIndex,
                    contig = chromosome
            }
        }

        call GatherLumpy {
            input:
                lumpyVCFs = LumpyChrom.lumpyOutput,
                bamBase = P2Prep.bamBase
        }
    }

    # output {
    #     File? breakdancerCTX = GatherBreakdancer.breakdancerCTX
    #     File? breakdancerVCF = GatherBreakdancer.breakdancerVCF

    #     File? breakseqGFF = Breakseq.breakseqGFF
    #     File? breakseq_genotypedGFF = Breakseq.breakseq_genotypedGFF
    #     File? breakseqVCF = Breakseq.breakseqVCF
    #     File? breakseqVCFindex = Breakseq.breakseqVCFindex
    #     File? breakseqBAM = Breakseq.breakseqBAM

    #     File? CNVnatorOutput = GatherCNVnator.CNVnatorOutput
    #     File? CNVnatorVCF = GatherCNVnator.CNVnatorVCF

    #     File? dellyDel = GatherDelly.dellyDeletion
    #     File? dellyDup = GatherDelly.dellyDuplication
    #     File? dellyIns = GatherDelly.dellyInsertion
    #     File? dellyInv = GatherDelly.dellyInversion

    #     File? mantaVCF = Manta.mantaVCF
    #     File? mantaStats = Manta.mantaStats
    #     File? mantaVariants = Manta.mantaVariants
    # }
}

###
# MULTI-PURPOSE TASKS
###
# P2Prep: Generates contigs and bamBase string for later use
task P2Prep {
    input {
        File inputBam
        Boolean filterContigs
    }

    command <<<
        samtools view -H "~{inputBam}" | python /opt/bin/get_contigs.py "~{filterContigs}" > contigs
    >>>

    Int diskGb = ceil(2.0 * size(inputBam, "G"))
    
    runtime {
        docker : "szarate/p2_prep:v0.0.1"
        disks : "local-disk ${diskGb} SSD"
    }

    output {
        File contigs = "contigs"
        String bamBase = '~{basename(inputBam,".bam")}'
    }
}

# SplitByChrom: Splits a BAM file into a given chromosome using sambamba
task SplitByChrom {
    input {
        File inputBam
        File inputBai
        String contig
    }

    command <<<
        sambamba view -h -f bam -t "$(nproc)" "~{inputBam}" "~{contig}" > "chr.~{contig}.bam"
        sambamba index -t "$(nproc)" "chr.~{contig}.bam"
    >>>

    Int diskGb = ceil(2.0 * size(inputBam, "G"))

    runtime {
        docker : "mgibio/sambamba-cwl:0.6.4"
        disks : "local-disk ${diskGb} SSD"
    }

    output {
        File splitBam = "chr.~{contig}.bam"
        File splitBai = "chr.~{contig}.bam.bai"
    }
}

task LumpyChrom {
    input {
        File inputBam
        File inputBai
        File refFasta
        File refIndex
        String contig
    }

    String refBase = basename(refFasta)
    String lumpyExclude = if (refBase == "*b37*") then "-x /opt/b37.bed" else (if refBase == "*hg38*" then "-x /opt/hg38.bed" else (if refBase == "*hg19" then "-x /opt/hg19.bed" else ""))

    command <<<
        lumpyexpress -B "~{inputBam}" -o "lumpy.~{contig}.vcf" "~{lumpyExclude}" -k
    >>>

    runtime {
        docker : "szarate/lumpy-sv:v0.3.0"
    }

    output {
        File lumpyOutput = "lumpy.~{contig}.vcf"
    }
}

task GatherLumpy {
    input {
        Array[File] lumpyVCFs
        String bamBase
    }

    command <<<
        python /opt/bin/convert_header.py "~{bamBase}" "~{sep = ' ' lumpyVCFs}" | vcf-sort -c | uniq > "~{bamBase}.lumpy.vcf"

        python /opt/bin/vcf2bedpe.py -i "~{bamBase}.lumpy.vcf" -o "~{bamBase}.lumpy.gff"
        python /opt/bin/lumpy2merge.py "~{bamBase}.lumpy.gff" "${prefix}" 1.0

        ls -sh
    >>>

    runtime {
        docker : "szarate/lumpy-sv:v0.3.0"
    }

    output {
        File lumpyGFF = "~{bamBase}.lumpy.gff"
        File lumpyVCF = "~{bamBase}.lumpy.vcf"
    }
}

###
# BREAKDANCER
###
# task PrepareBreakdancer {
#     input {
#         File inputBam
#     }

#     command <<<
#         bam2cfg -o breakdancer.cfg "~{inputBam}"
#     >>>

#     Int diskGb = ceil(2.0 * size(inputBam, "G"))

#     runtime {
#         docker : "szarate/breakdancer:v1.4.3"
#         disks : "local-disk ${diskGb} SSD"
#     }

#     output {
#         File configFile = "breakdancer.cfg"
#     }
# }

# task BreakdancerChrom {
#     input {
#         File inputBam
#         File inputBai
#         File refFasta
#         File refIndex
#         File configFile
#         String contig
#     }

#     command <<<
#         breakdancer-max "~{configFile}" "~{inputBam}" -o ~{contig} > breakdancer-~{contig}.ctx
#     >>>

#     Int diskGb = ceil(2.0 * size(inputBam, "G"))

#     runtime {
#         docker : "szarate/breakdancer:v1.4.3"
#         disks : "local-disk ${diskGb} SSD"
#     }

#     output {
#         File breakdancerOutput = "breakdancer-~{contig}.ctx"
#     }
# }

# task GatherBreakdancer {
#     input {
#         Array[File] breakdancerCtx
#         String bamBase
#     }

#     command <<<
#         cat ~{sep=' ' breakdancerCtx} > "~{bamBase}.breakdancer.ctx"

#         python /opt/bin/merge_files.py 1.0 "~{bamBase}.breakdancer.ctx" "~{bamBase}"
#         python /opt/bin/ctx_to_vcf.py < "~{bamBase}.breakdancer.ctx" > "~{bamBase}.breakdancer.vcf"
#     >>>

#     runtime {
#         docker : "szarate/breakdancer:v1.4.3"
#     }

#     output {
#         File breakdancerCTX = "~{bamBase}.breakdancer.ctx"
#         File breakdancerVCF = "~{bamBase}.breakdancer.vcf"
#     }
# }

# ###
# # BREAKSEQ
# ###
# task Breakseq {
#     input {
#         File inputBam
#         File inputBai
#         File refFasta
#         File refIndex
#     }

#     String bamBase='~{basename(inputBam,".bam")}'
#     String refBase = basename(refFasta)
#     String breakpointLibrary = if (refBase == "*hg19*") then "/breakseq2_bplib_20150129.hg19/breakseq2_bplib_20150129.hg19.gff" else (if refBase == "*hg38*" then "/bplib.hg38.gff" else "/breakseq2_bplib_20150129.hs37d5/breakseq2_bplib_20150129.gff")

#     command <<<
#         mkdir -p "breakseq2"
#         gunzip "~{refFasta}"

#         refName="~{refFasta}"
#         refName="${refName%.gz}"

#         /miniconda/bin/run_breakseq2.py \
#             --reference "${refName}" \
#             --bams "~{inputBam}" \
#             --work breakseq2 \
#             --bwa /miniconda/bin/bwa \
#             --samtools /miniconda/bin/samtools \
#             --bplib_gff "~{breakpointLibrary}" \
#             --nthreads "$(nproc)" \
#             --sample "~{bamBase}"

#             mv breakseq2/breakseq.vcf.gz "~{bamBase}.breakseq.vcf.gz"
#             mv breakseq2/breakseq.vcf.gz.tbi "~{bamBase}.breakseq.vcf.gz.tbi"
#             mv breakseq2/breakseq.gff "~{bamBase}.breakseq.gff"
#             mv breakseq2/breakseq_genotyped.gff "~{bamBase}_genotyped.breakseq.gff"
#             mv breakseq2/final.bam "~{bamBase}.breakseq.bam"
#     >>>
    
#     Int diskGb = ceil(2.0 * size(inputBam, "G"))

#     runtime {
#         docker : "szarate/breakseq2:v2.2"
#         disks : "local-disk ${diskGb} SSD"
#         cpu : 8
#     }

#     output {
#         File breakseqGFF = "${bamBase}.breakseq.gff"
#         File breakseq_genotypedGFF = "${bamBase}_genotyped.breakseq.gff"
#         File breakseqVCF = "${bamBase}.breakseq.vcf.gz"
#         File breakseqVCFindex = "${bamBase}.breakseq.vcf.gz.tbi"
#         File breakseqBAM = "${bamBase}.breakseq.bam"
#     }
# }

# ###
# # CNVNATOR
# ###
# task CNVnatorChrom {
#     input {
#         File inputBam
#         File inputBai
#         File refFasta
#         File refIndex
#         String contig
#     }

#     command <<<
#         cnvnator -root output.root"~{contig}" -chrom "~{contig}" -genome "~{refFasta}" -tree "~{inputBam}"
#         cnvnator -root output.root"~{contig}" -chrom "~{contig}" -genome "~{refFasta}" -his 100
#         cnvnator -root output.root"~{contig}" -chrom "~{contig}" -genome "~{refFasta}" -stat 100
#         cnvnator -root output.root"~{contig}" -chrom "~{contig}" -genome "~{refFasta}" -partition 100
#         cnvnator -root output.root"~{contig}" -chrom "~{contig}" -genome "~{refFasta}" -call 100  > "output.cnvnator_calls-~{contig}"
#     >>>

#     Int diskGb = ceil(2.0 * size(inputBam, "G"))

#     runtime {
#         docker : "szarate/cnvnator:v0.4.1"
#         disks : "local-disk ${diskGb} SSD"
#         cpu : 8
#     }

#     output {
#         File CNVnatorOutput = "output.cnvnator_calls-~{contig}"
#     }
# }

# task GatherCNVnator {
#     input {
#         Array[File] CNVnatorCalls
#         String bamBase
#     }

#     command <<<
#         cat ~{sep=' ' CNVnatorCalls} > "~{bamBase}.cnvnator.output"

#         perl /opt/bin/cnvnator2vcf.pl "~{bamBase}.cnvnator.output" > "~{bamBase}.cnvnator.vcf"
#     >>>

#     runtime {
#         docker : "szarate/cnvnator:v0.4.1"
#     }

#     output {
#         File CNVnatorOutput = "~{bamBase}.cnvnator.output"
#         File CNVnatorVCF = "~{bamBase}.cnvnator.vcf"
#     }
# }

# ###
# # DELLY
# ###
# task DellyChrom {
#     input {
#         File inputBam
#         File inputBai
#         File refFasta
#         File refIndex
#         String contig
#     }

#     command <<<
#         delly call -t DEL -o "~{contig}.delly.deletion.vcf" -g "~{refFasta}" "~{inputBam}"
#         delly call -t DUP -o "~{contig}.delly.duplication.vcf" -g "~{refFasta}" "~{inputBam}"
#         delly call -t INS -o "~{contig}.delly.insertion.vcf" -g "~{refFasta}" "~{inputBam}"
#         delly call -t INV -o "~{contig}.delly.inversion.vcf" -g "~{refFasta}" "~{inputBam}"
#     >>>

#     runtime {
#         docker : "szarate/delly:v0.8.3"
#         cpu : 4
#     }

#     output {
#         File dellyDeletion = "~{contig}.delly.deletion.vcf"
#         File dellyDuplication = "~{contig}.delly.duplication.vcf"
#         File dellyInsertion = "~{contig}.delly.insertion.vcf"
#         File dellyInversion = "~{contig}.delly.inversion.vcf"
#     }
# }

# task GatherDelly {
#     input {
#         Array[File] dellyDelVCFs
#         Array[File] dellyDupVCFs
#         Array[File] dellyInsVCFs
#         Array[File] dellyInvVCFs
#         String bamBase
#     }

#     command <<<
#         python /opt/bin/convert_header.py "~{bamBase}" "~{sep=' ' dellyDelVCFs}" | vcf-sort -c | uniq > "~{bamBase}.delly.deletion.vcf"
#         python /opt/bin/convert_header.py "~{bamBase}" "~{sep=' ' dellyDupVCFs}" | vcf-sort -c | uniq > "~{bamBase}.delly.duplication.vcf"
#         python /opt/bin/convert_header.py "~{bamBase}" "~{sep=' ' dellyInsVCFs}" | vcf-sort -c | uniq > "~{bamBase}.delly.insertion.vcf"
#         python /opt/bin/convert_header.py "~{bamBase}" "~{sep=' ' dellyInvVCFs}" | vcf-sort -c | uniq > "~{bamBase}.delly.inversion.vcf"
#     >>>

#     runtime {
#         docker : "szarate/delly:v0.8.3"
#     }

#     output {
#         File dellyDeletion = "~{bamBase}.delly.deletion.vcf"
#         File dellyDuplication = "~{bamBase}.delly.duplication.vcf"
#         File dellyInsertion = "~{bamBase}.delly.insertion.vcf"
#         File dellyInversion = "~{bamBase}.delly.inversion.vcf"
#     }
# }

# ###
# # MANTA
# ###
# task Manta {
#     input {
#         File inputBam
#         File inputBai
#         File refFasta
#         File refIndex
#         File contigs
#     }

#     String bamBase='~{basename(inputBam,".bam")}'

#     command <<<
#         mkdir -p "manta"
#         gunzip "~{refFasta}"

#         refName="~{refFasta}"
#         refName="${refName%.gz}"
#         region_string=""

#         while read line; do
#             region_string="$region_string --region=$line"
#         done < "~{contigs}"

#         python /usr/local/bin/configManta.py --referenceFasta "${refName}" --normalBam "~{inputBam}" --runDir manta $region_string

#         python manta/runWorkflow.py -m local -j "$(nproc)"

#         tar -czf stats.tar.gz -C manta/results/stats/ .
#         tar -czf variants.tar.gz -C manta/results/variants/ .

#         mv manta/results/variants/diploidSV.vcf.gz "~{bamBase}.manta.vcf.gz"
#         mv stats.tar.gz "~{bamBase}_stats.manta.vcf.gz"
#         mv variants.tar.gz "~{bamBase}_variants.manta.vcf.gz"
#     >>>

#     Int diskGb = ceil(2.0 * size(inputBam, "G"))

#     runtime {
#         docker : "szarate/manta:v1.6.0"
#         disks : "local-disk ${diskGb} SSD"
#         cpu : 8
#     }

#     output {
#         File mantaVCF = "~{bamBase}.manta.vcf.gz"
#         File mantaStats = "~{bamBase}_stats.manta.vcf.gz"
#         File mantaVariants = "~{bamBase}_variants.manta.vcf.gz"
#     }
# }