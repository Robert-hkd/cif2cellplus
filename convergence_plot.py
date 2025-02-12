#!/usr/bin/env python

import pandas as pd
import matplotlib.pyplot as plt
import os
from math import sqrt,ceil
import re
import glob



# while 1:
#   try: 
#     nu = int(input("The numbers of unit in the system: "))
#     break
#   except: pass

fi = '*.castep'

# fi = input("Filename: (default: *.castep)")
# if fi == '': 
#   fi = '*.castep'
# elif fi[-7:] != ".castep":
#   fi = fi + ".castep"





cut_energy = re.compile(r"plane wave basis set cut-off\s*:\s*(\d+)\.") #get cuttoff energies for x axis
energies = []

k_points = re.compile(r"Number of kpoints used =\s*(\d+)") #get number of k points for x axis
k_vals = []

header = re.compile(r"x{60}") # get number of sites
found = 0
nu = 0

with open(glob.glob(fi)[0], 'r') as file:
  for line in file:

    energy_match = cut_energy.search(line)
    if energy_match:
        energies.append(int(energy_match.group(1)))

    k_match = k_points.search(line)
    if k_match:
        k_vals.append(int(k_match.group(1)))


    #finds number of sites
    if found == 1:
      nu += 1

    if header.search(line):
      found += 1
nu = nu - 4


x_label = 'Energy Cutoff (eV)'
m = ""
try:
  if energies[-1] != energies[-2]:
    x_vals = energies
    folder = "plots_energies"
  else:
    x_vals = k_vals
    x_label = 'Number of k-points'
    m="o"
    folder = 'plots_kpoints'
except:
  x_vals = energies
  folder = "plots_energies"
  

try: 
  #if x_label == 'Number of k-points':
  #    os.mkdir('plots_kpoints')
  #else:
  #    os.mkdir('plots_energies')
  os.mkdir(folder)

except: pass


os.system(f'grep "Cq(MHz)" {fi} -A {nu} | sed "s/|//" > {folder}/read.txt') # read the castep file


if (os.system(f'grep -q "Aniso" {folder}/read.txt') != 0): # read if it's EFG or NMR
  raw = pd.read_table(folder+"/read.txt", sep='\s+', names = ['Species', 'Ion', 'Cq', 'asym', '|'])
  pobject = ['Cq', 'asym']
else:
  raw = pd.read_table(folder+"/read.txt", sep='\s+', names = ['Species', 'Ion', 'iso', 'aniso', 'asym', 'Cq', 'Eta', '|'])
  pobject = ['iso', 'aniso', 'asym', 'Cq', 'Eta']

# while 1: # Choose things to plot
#   try:
#     nloop =  input(f'(1-{len(pobject)}) for {pobject}, 0 for everything, default: 1\nPlease input: ')
#     if nloop == '': nloop = 0
#     else:
#       nloop = int(nloop)
#       if nloop > len(pobject): raise
#       else: nloop = nloop - 1
#     if nloop != -1: pobject = [pobject[nloop]]
#     break
#   except: pass


n = raw.shape[0] # Number of ions in the whole calculation
species = []
for i in range(1, 1+nu):
    if raw.get("Species")[i] not in species:
        species.append(raw.get("Species")[i])



for param in pobject:
  data = pd.DataFrame()
  i = 1
  count = 0
  while i < n:
      temp = raw.iloc[i:i+nu,0:-1]
      temp[param] = pd.to_numeric(temp[param], errors='coerce')
      temp.insert(0, "Spion", temp.loc[:,"Species"]+'-'+temp.loc[:,"Ion"])
      avg = temp.groupby("Spion")[param].mean()
      
      if param == 'Cq':
        data.insert(count, count, abs(avg)) # x axis is just from 0 to count. Have no plan to update it because we have series of convergence
      else:
        data.insert(count, count, avg) # x axis is just from 0 to count. Have no plan to update it because we have series of convergence

      
      count = count + 1
      i = i + nu + 2
  #print(data)
  data = data.T
  # data.to_csv(f'plots/{param}.csv', index=False)



  j = 1
  for i in species:
    plt.subplot(ceil(sqrt(len(species))), ceil(sqrt(len(species))), j)
    plt.xlabel(x_label) 
    for Index in range(nu):
      try:
        y_vals = list(data[i + '-' + str(Index+1)])
        plt.plot(x_vals[0:len(y_vals)],y_vals, marker = m, markersize=3)
      except:
        pass
    #Legend = []
    #for t in range(1,Index):
    #  Legend.append(i + '-' + str(t))
    #plt.legend(Legend)
    plt.title(i)
    j += 1
  plt.tight_layout()

 # if x_label == 'Number of k-points':
 #   plt.savefig(f'plots_kpoints/{param}_plot.png')
 # else:
 #   plt.savefig(f'plots_energies/{param}_plot.png')

  plt.savefig(f'{folder}/{param}_plot.png')
  plt.close()
